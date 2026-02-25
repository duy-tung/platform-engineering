package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

// Version được set lúc build bằng -ldflags
var Version = "dev"

type HealthResponse struct {
	Status    string `json:"status"`
	Version   string `json:"version"`
	Timestamp string `json:"timestamp"`
}

type DBCheckResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	Latency string `json:"latency,omitempty"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	// Health check — K8s liveness probe dùng endpoint này
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(HealthResponse{
			Status:    "ok",
			Version:   Version,
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		})
	})

	// Readiness probe — kiểm tra app có sẵn sàng nhận traffic không
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
	})

	// Version endpoint
	mux.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		hostname, _ := os.Hostname()
		json.NewEncoder(w).Encode(map[string]string{
			"version":  Version,
			"hostname": hostname,
		})
	})

	// DB check — kiểm tra kết nối database
	mux.HandleFunc("/db-check", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		dsn := os.Getenv("DATABASE_URL")
		if dsn == "" {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(DBCheckResponse{
				Status:  "error",
				Message: "DATABASE_URL not configured",
			})
			return
		}

		start := time.Now()
		db, err := sql.Open("postgres", dsn)
		if err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(DBCheckResponse{
				Status:  "error",
				Message: fmt.Sprintf("connection error: %v", err),
			})
			return
		}
		defer db.Close()

		err = db.Ping()
		latency := time.Since(start)

		if err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(DBCheckResponse{
				Status:  "error",
				Message: fmt.Sprintf("ping error: %v", err),
			})
			return
		}

		json.NewEncoder(w).Encode(DBCheckResponse{
			Status:  "ok",
			Message: "database connected",
			Latency: latency.String(),
		})
	})

	// Root — welcome page
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"service": "platform-api",
			"version": Version,
			"docs":    "/health, /ready, /version, /db-check",
		})
	})

	log.Printf("🚀 platform-api %s starting on :%s", Version, port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// TODO: Week 7 — Add HPA metrics endpoint

