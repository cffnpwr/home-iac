package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"reflect"
	"strings"
	"time"

	"github.com/go-playground/validator/v10"
)

// Terraformのplanが応答の無い接続で止まり続けないための上限
const requestTimeout = 30 * time.Second

type query struct {
	URL string `json:"url" validate:"required,url"`
}

type result struct {
	URL string `json:"url"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	var input query
	if err := json.NewDecoder(os.Stdin).Decode(&input); err != nil {
		return fmt.Errorf("invalid input value: %v", err)
	}
	if err := validateQuery(input); err != nil {
		return err
	}

	client := &http.Client{
		Timeout: requestTimeout,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, input.URL, nil)
	if err != nil {
		return fmt.Errorf("create request for %s: %v", input.URL, err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request %s: %v", input.URL, err)
	}
	defer resp.Body.Close()

	switch {
	case resp.StatusCode >= http.StatusOK && resp.StatusCode < http.StatusMultipleChoices:
		return json.NewEncoder(os.Stdout).Encode(result(input))
	case resp.StatusCode >= http.StatusMultipleChoices && resp.StatusCode < http.StatusBadRequest:
		location, locationErr := resp.Location()
		if locationErr == nil {
			return json.NewEncoder(os.Stdout).Encode(result{URL: location.String()})
		}
	}

	return fmt.Errorf(
		"unexpected response from %q: status: %d, location: %q, expected 2xx or 3xx with location",
		input.URL,
		resp.StatusCode,
		resp.Header.Get("Location"),
	)
}

func validateQuery(input query) error {
	validate := validator.New(validator.WithRequiredStructEnabled())
	validate.RegisterTagNameFunc(func(field reflect.StructField) string {
		return strings.Split(field.Tag.Get("json"), ",")[0]
	})

	err := validate.Struct(input)
	if err == nil {
		return nil
	}

	var fieldErrors validator.ValidationErrors
	if !errors.As(err, &fieldErrors) {
		return err
	}

	messages := make([]string, 0, len(fieldErrors))
	for _, fieldError := range fieldErrors {
		messages = append(
			messages,
			fmt.Sprintf(
				"input value %s does not satisfy %s: %q",
				fieldError.Field(),
				fieldError.Tag(),
				fieldError.Value(),
			),
		)
	}

	return errors.New(strings.Join(messages, "; "))
}
