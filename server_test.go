// server_test
package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestMultipartRequest(t *testing.T) *http.Request {
	b := strings.NewReader(strings.Replace(message, "\n", "\r\n", -1))
	req, err := http.NewRequest("POST", "/", b)
	if err != nil {
		t.Fatal("NewRequest:", err)
	}
	ctype := fmt.Sprintf(`multipart/form-data; boundary="%s"`, boundary)
	req.Header.Set("Content-type", ctype)
	return req
}

func TestConvert(t *testing.T) {
	start()
	req := newTestMultipartRequest(t)
	w := httptest.NewRecorder()
	http.DefaultServeMux.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("Status code should be %v, was %d", http.StatusOK, w.Code)
	}
	t.Log(w.Body.String())
}

const (
	fileaContents     = "<html><body>This is a test file.</body></html>"
	filebContents     = "<html><body>Another test file.</body></html>"
	orientationaValue = "L"
	orientationbValue = "P"
	pageSizeaValue    = "A3"
	pageSizebValue    = "A4"
	boundary          = `MyBoundary`
)

const message = `
--` + boundary + `
Content-Disposition: form-data; name="file"; filename="filea.html"
Content-Type: text/html

` + fileaContents + `
--` + boundary + `
Content-Disposition: form-data; name="file"; filename="fileb.html"
Content-Type: text/html

` + filebContents + `
--` + boundary + `
Content-Disposition: form-data; name="orientation"

` + orientationaValue + `
--` + boundary + `
Content-Disposition: form-data; name="orientation"

` + orientationbValue + `
--` + boundary + `
Content-Disposition: form-data; name="page_size"

` + pageSizeaValue + `
--` + boundary + `
Content-Disposition: form-data; name="page_size"

` + pageSizebValue + `
--` + boundary + `
Content-Disposition: form-data; name="double_side"

Y
--` + boundary + `
Content-Disposition: form-data; name="margin-top"

30
--` + boundary + `
Content-Disposition: form-data; name="margin-top"

0
--` + boundary + `--
`
