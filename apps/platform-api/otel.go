// Package main — OpenTelemetry SDK setup for platform-api
// Initializes TracerProvider (OTLP → Tempo) + MeterProvider (Prometheus export)
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/prometheus"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// setupOTelSDK initializes OpenTelemetry with traces + metrics.
// Returns a shutdown function that flushes and stops all providers.
func setupOTelSDK(ctx context.Context) (shutdown func(context.Context) error, err error) {
	var shutdownFuncs []func(context.Context) error

	// shutdown combines all cleanup functions into one.
	shutdown = func(ctx context.Context) error {
		var errs []error
		for _, fn := range shutdownFuncs {
			errs = append(errs, fn(ctx))
		}
		return errors.Join(errs...)
	}

	// ---- Resource: identifies this service in traces/metrics ----
	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(getEnv("OTEL_SERVICE_NAME", "platform-api")),
			semconv.ServiceVersion(Version),
			semconv.DeploymentEnvironmentKey.String(getEnv("OTEL_ENVIRONMENT", "development")),
		),
	)
	if err != nil {
		return shutdown, fmt.Errorf("creating OTel resource: %w", err)
	}

	// ---- Propagator: W3C TraceContext for distributed tracing ----
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// ---- TracerProvider: OTLP HTTP → OTel Collector → Tempo ----
	otlpEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otlpEndpoint != "" {
		traceExporter, traceErr := otlptracehttp.New(ctx,
			otlptracehttp.WithEndpoint(otlpEndpoint),
			otlptracehttp.WithInsecure(), // Internal cluster traffic
		)
		if traceErr != nil {
			return shutdown, fmt.Errorf("creating OTLP trace exporter: %w", traceErr)
		}

		tp := sdktrace.NewTracerProvider(
			sdktrace.WithBatcher(traceExporter,
				sdktrace.WithBatchTimeout(5*time.Second),
			),
			sdktrace.WithResource(res),
			sdktrace.WithSampler(sdktrace.AlwaysSample()), // Sample 100% for learning
		)
		shutdownFuncs = append(shutdownFuncs, tp.Shutdown)
		otel.SetTracerProvider(tp)
	}

	// ---- MeterProvider: Prometheus exporter (scraped at /metrics) ----
	promExporter, err := prometheus.New()
	if err != nil {
		return shutdown, fmt.Errorf("creating Prometheus exporter: %w", err)
	}

	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(promExporter),
		sdkmetric.WithResource(res),
	)
	shutdownFuncs = append(shutdownFuncs, mp.Shutdown)
	otel.SetMeterProvider(mp)

	return shutdown, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
