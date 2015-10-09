package main

import (
	"flag"
	"fmt"
	"github.com/kardianos/service"
	_ "golang.org/x/tools/go/ssa"
	"log"
	"os"
	"runtime"
	"sync"
)

var (
	logger     service.Logger
	loggerLock sync.Mutex
	svcFlag    *string
	portFlag   *int
)

func logInfof(format string, a ...interface{}) error {
	loggerLock.Lock()
	defer loggerLock.Unlock()
	if logger != nil {
		return logger.Infof(format, a...)
	}
	return nil
}
func logError(v ...interface{}) error {
	loggerLock.Lock()
	defer loggerLock.Unlock()
	if logger != nil {
		return logger.Error(v)
	}
	return nil
}

// Program structures.
//  Define Start and Stop methods.
type program struct {
	exit chan struct{}
}

func (p *program) Start(s service.Service) error {
	if service.Interactive() {
		logInfof("Service \"%s\" is running in terminal.", serviceDisplayName())
	} else {
		logInfof("Service \"%s\" is running under service manager.", serviceDisplayName())
	}
	p.exit = make(chan struct{})

	// Start should not block. Do the actual work async.
	go p.run()
	return nil
}
func (p *program) run() {
	start()
	logInfof("Service \"%s\" is started.", serviceDisplayName())

	for {
		select {
		case <-p.exit:
			return
		}
	}
}
func (p *program) Stop(s service.Service) error {
	// Any work in Stop should be quick, usually a few seconds at most.
	logInfof("Service \"%s\" is stopped.", serviceDisplayName())
	close(p.exit)
	return nil
}

// Service setup.
//   Define service config.
//   Create the service.
//   Setup the logger.
//   Handle service controls (optional).
//   Run the service.
func main() {
	runtime.GOMAXPROCS(runtime.NumCPU())

	flag.Usage = usage
	svcFlag = flag.String("service", "", fmt.Sprintf("Control the system service. Valid actions: %q\n", service.ControlAction))
	portFlag = flag.Int("port", 17000, "    Port number")
	flag.Parse()

	if *portFlag == 0 {
		usage()
		os.Exit(2)
	}

	svcConfig := &service.Config{
		Name:        serviceName(),
		DisplayName: serviceDisplayName(),
		Description: serviceDisplayName(),
		Arguments:   []string{fmt.Sprintf("-port=%d", *portFlag)},
	}

	prg := &program{}
	s, err := service.New(prg, svcConfig)
	if err != nil {
		log.Fatal(err)
	}
	errs := make(chan error, 5)
	func() {
		loggerLock.Lock()
		defer loggerLock.Unlock()
		logger, err = s.Logger(errs)
		if err != nil {
			log.Fatal(err)
		}
	}()

	go func() {
		for {
			err := <-errs
			if err != nil {
				log.Print(err)
			}
		}
	}()

	if len(*svcFlag) != 0 {
		err := service.Control(s, *svcFlag)
		if err != nil {
			log.Printf("Valid actions: %q\n", service.ControlAction)
			log.Fatal(err)
		}
		return
	}
	err = s.Run()
	if err != nil {
		logError(err)
	}
}

func serviceName() string {
	return fmt.Sprintf("ipdf_%d", *portFlag)
}

func serviceDisplayName() string {
	return fmt.Sprintf("Internet/Intranet HTML to Pdf Converter (Port = %d)", *portFlag)
}

const usageTemplate = `ipdf is Internet/Intranet HTML to Pdf Converter

Usage: ipdf commands

The commands are:
`

func usage() {
	fmt.Fprintln(os.Stderr, usageTemplate)
	flag.PrintDefaults()
}
