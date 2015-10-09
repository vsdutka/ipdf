// server
package main

import (
	"bytes"
	"code.google.com/p/go-uuid/uuid"
	"fmt"
	"github.com/kardianos/osext"
	"gopkg.in/errgo.v1"
	"io"
	//	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath
	"
	"regexp"
	"strconv"
	"strings"
)

var basePath string

func init() {
	exeName, err := osext.Executable()

	if err == nil {
		exeName, err = filepath.Abs(exeName)
		if err == nil {
			basePath = filepath.Dir(exeName)
		}
	}
}
func html2pdf(args ...string) error {
	cmdSlice := []string{}

	for _, line := range args {
		cmdSlice = append(cmdSlice, line)
	}

	cmd := exec.Command(basePath+"\\wkhtmltopdf.exe", cmdSlice...)

	var b bytes.Buffer
	cmd.Stderr = &b
	if err := cmd.Run(); err != nil {
		return errgo.New(b.String())
	}
	return nil
}

func pdfPageCount(fname string) (int, error) {
	cmdSlice := []string{fname, "dump_data"}
	cmd := exec.Command(basePath+"\\pdftk.exe", cmdSlice...)

	var out bytes.Buffer
	cmd.Stdout = &out
	err := cmd.Run()
	if err != nil {
		return 0, err
	}
	//NumberOfPages: 1
	var r = regexp.MustCompile(`NumberOfPages: [0-9]+`)
	s := r.FindAllString(out.String(), -1)
	if len(s) != 1 {
		return 0, errgo.New("Number of pages does not exists")
	}
	return strconv.Atoi(strings.Replace(s[0], "NumberOfPages: ", "", -1))
}

func pdfMerge(fileNames ...string) ([]byte, error) {
	cmdSlice := []string{}

	for _, line := range fileNames {
		cmdSlice = append(cmdSlice, line)
	}
	cmdSlice = append(cmdSlice, "output")
	cmdSlice = append(cmdSlice, "-")

	cmd := exec.Command(basePath+"\\pdftk.exe", cmdSlice...)

	var out bytes.Buffer
	cmd.Stdout = &out
	var b bytes.Buffer
	cmd.Stderr = &b
	err := cmd.Run()
	if err != nil {
		return nil, errgo.New(b.String())
	}
	return out.Bytes(), err
}

func responseError(w http.ResponseWriter, code int, message string) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(code)
	w.Write([]byte(message))
}
func start() {
	http.HandleFunc("/", WriteLog(func(w http.ResponseWriter, r *http.Request) {
		b, err := func() ([]byte, error) {
			if err := r.ParseMultipartForm(64 << 20); err != nil {
				return nil, errgo.Newf("Parse multipart - error: %s", err.Error())
			}
			if len(r.MultipartForm.File["file"]) == 0 {
				return nil, errgo.New("Files do not exists")
			}

			var dirName = basePath + "\\tmp\\" + uuid.New()

			if err := os.MkdirAll(dirName, os.ModeDir); err != nil {
				return nil, errgo.Newf("Make dir \"%s\" - error: %s", dirName, err.Error())
			}

			defer os.RemoveAll(dirName)

			ds := r.FormValue("double_side")
			fileNames := make([]string, 0)
			for k, v := range r.MultipartForm.File["file"] {
				args := []string{"--load-error-handling", "ignore"}

				if v, ok := r.MultipartForm.Value["orientation"]; ok {
					args = append(args, "-O")
					switch v[k] {
					case "L":
						{
							args = append(args, "Landscape")
						}
					default:
						{
							args = append(args, "Portrait")
						}
					}
				}

				if v, ok := r.MultipartForm.Value["page_size"]; ok {
					args = append(args, "--page-size")
					args = append(args, v[k])
				}
				if v, ok := r.MultipartForm.Value["margin-bottom"]; ok {
					args = append(args, "--margin-bottom")
					args = append(args, v[k])
				}
				if v, ok := r.MultipartForm.Value["margin-left"]; ok {
					args = append(args, "--margin-left")
					args = append(args, v[k])
				}
				if v, ok := r.MultipartForm.Value["margin-top"]; ok {
					args = append(args, "--margin-top")
					args = append(args, v[k])
				}
				if v, ok := r.MultipartForm.Value["margin-right"]; ok {
					args = append(args, "--margin-right")
					args = append(args, v[k])
				}

				f, err := v.Open()
				if err != nil {
					return nil, errgo.Newf("File \"%s\" open - error: %s", v.Filename, err.Error())
				}
				fileName := fmt.Sprintf("%s\\%s.pdf", dirName, v.Filename)
				f1, err := os.OpenFile(fmt.Sprintf("%s\\%s", dirName, v.Filename), os.O_WRONLY|os.O_CREATE, 0666)
				if err != nil {
					return nil, errgo.Newf("File \"%s\" save - error: %s", v.Filename, err.Error())
				}
				defer f1.Close()
				io.Copy(f1, f)

				args = append(args, fmt.Sprintf("%s\\%s", dirName, v.Filename))
				args = append(args, fileName)

				if err := html2pdf(args...); err != nil {
					return nil, errgo.Newf("File \"%s\" convert - error: %s", v.Filename, err.Error())
				}
				fileNames = append(fileNames, fileName)
				if ds == "Y" {
					pc, err2 := pdfPageCount(fileName)
					if err2 != nil {
						return nil, errgo.Newf("File \"%s\" page count retrive - error: %s", fileName, err2.Error())
					}
					if pc%2 == 1 {
						fileNames = append(fileNames, basePath+"\\files\\empty.pdf")
					}
				}
			}
			b, err := pdfMerge(fileNames...)
			if err != nil {
				return nil, errgo.Newf("Merge files - error: %s", err.Error())
			}
			return b, nil

		}()
		if err != nil {
			responseError(w, http.StatusInternalServerError, err.Error())
			return
		}
		w.Header().Set("Content-type", "application/pdf")
		w.Write(b)
	}, basePath+"\\log\\"))
	go http.ListenAndServe(":17000", nil)
}
