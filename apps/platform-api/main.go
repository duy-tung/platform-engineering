// Package main — platform-api service with OpenTelemetry observability
package main

import (
	"context"
	"database/sql"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"time"

	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// Version được set lúc build bằng -ldflags
var Version = "dev"

//go:embed static
var staticFS embed.FS

// tracer for manual span creation in handlers
var tracer = otel.Tracer("platform-api")

// ---- Models ----
type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

type HealthResponse struct {
	Status    string `json:"status"`
	Version   string `json:"version"`
	Timestamp string `json:"timestamp"`
}

// ---- Global DB ----
var db *sql.DB

func buildDSN() string {
	// Prefer individual env vars (big-tech pattern: avoids URL-encoding issues)
	host := os.Getenv("DB_HOST")
	if host != "" {
		port := os.Getenv("DB_PORT")
		if port == "" {
			port = "5432"
		}
		user := os.Getenv("DB_USER")
		password := os.Getenv("DB_PASSWORD")
		dbname := os.Getenv("DB_NAME")
		sslmode := os.Getenv("DB_SSLMODE")
		if sslmode == "" {
			sslmode = "disable"
		}
		// Use keyword=value format (no URL parsing, special chars safe)
		return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
			host, port, user, password, dbname, sslmode)
	}

	// Fallback: DATABASE_URL for backwards compatibility
	return os.Getenv("DATABASE_URL")
}

func initDB() {
	dsn := buildDSN()
	if dsn == "" {
		slog.Warn("DB_HOST (or DATABASE_URL) not set — DB features disabled")
		return
	}

	var err error
	for i := 0; i < 10; i++ {
		db, err = sql.Open("postgres", dsn)
		if err == nil {
			err = db.Ping()
		}
		if err == nil {
			break
		}
		slog.Warn("DB connection attempt failed",
			"attempt", i+1,
			"max", 10,
			"error", err,
		)
		time.Sleep(3 * time.Second)
	}
	if err != nil {
		slog.Error("Could not connect to DB after 10 attempts", "error", err)
		return
	}

	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Auto-migrate
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			name VARCHAR(100) NOT NULL,
			email VARCHAR(255) UNIQUE NOT NULL,
			created_at TIMESTAMP DEFAULT NOW()
		)
	`)
	if err != nil {
		slog.Error("Migration failed", "error", err)
		return
	}
	slog.Info("DB connected + migrated")
}

func main() {
	// Structured JSON logging
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	if err := run(); err != nil {
		slog.Error("Server failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	// ---- Initialize OpenTelemetry ----
	otelShutdown, err := setupOTelSDK(ctx)
	if err != nil {
		return fmt.Errorf("setting up OTel SDK: %w", err)
	}
	defer func() {
		err = errors.Join(err, otelShutdown(context.Background()))
	}()

	initDB()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	// ---- Health (no otelhttp wrapping — keep health checks lightweight) ----
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)
	mux.HandleFunc("/version", handleVersion)

	// ---- Prometheus metrics endpoint ----
	mux.Handle("/metrics", promhttp.Handler())

	// ---- CRUD Users ----
	mux.Handle("/users", http.HandlerFunc(handleUsers))
	mux.Handle("/users/", http.HandlerFunc(handleUserByID))

	// ---- DB check ----
	mux.Handle("/db-check", http.HandlerFunc(handleDBCheck))

	// ---- Root: serve UI ----
	mux.HandleFunc("/", handleRoot)

	// Wrap entire mux with otelhttp for HTTP metrics + trace propagation
	handler := otelhttp.NewHandler(mux, "platform-api",
		otelhttp.WithMessageEvents(otelhttp.ReadEvents, otelhttp.WriteEvents),
	)

	srv := &http.Server{
		Addr:         ":" + port,
		BaseContext:  func(net.Listener) context.Context { return ctx },
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		Handler:      handler,
	}

	slog.Info("platform-api starting",
		"version", Version,
		"port", port,
		"otel_endpoint", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
	)

	srvErr := make(chan error, 1)
	go func() {
		srvErr <- srv.ListenAndServe()
	}()

	select {
	case err = <-srvErr:
		return err
	case <-ctx.Done():
		stop()
	}

	return srv.Shutdown(context.Background())
}

// ---- Handlers ----

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(HealthResponse{
		Status:    "ok",
		Version:   Version,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	})
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db != nil {
		if err := db.Ping(); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]string{"status": "not ready", "error": err.Error()})
			return
		}
	}
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

func handleVersion(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	hostname, _ := os.Hostname()
	json.NewEncoder(w).Encode(map[string]string{
		"version":  Version,
		"hostname": hostname,
	})
}

func handleDBCheck(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	w.Header().Set("Content-Type", "application/json")

	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "error", "message": "DATABASE_URL not configured"})
		return
	}

	_, span := tracer.Start(ctx, "db.ping")
	start := time.Now()
	err := db.PingContext(ctx)
	latency := time.Since(start)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.End()
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "error", "message": err.Error()})
		return
	}
	span.SetAttributes(attribute.String("db.latency", latency.String()))
	span.End()

	json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"message": "database connected",
		"latency": latency.String(),
	})
}

func handleUsers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "database not available"})
		return
	}

	switch r.Method {
	case http.MethodGet:
		listUsers(r.Context(), w)
	case http.MethodPost:
		createUser(r.Context(), w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
	}
}

func handleUserByID(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "database not available"})
		return
	}

	idStr := strings.TrimPrefix(r.URL.Path, "/users/")
	if idStr == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "missing user id"})
		return
	}

	switch r.Method {
	case http.MethodGet:
		getUser(r.Context(), w, idStr)
	case http.MethodPut:
		updateUser(r.Context(), w, r, idStr)
	case http.MethodDelete:
		deleteUser(r.Context(), w, idStr)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
	}
}

// ---- DB Operations (with tracing) ----

func listUsers(ctx context.Context, w http.ResponseWriter) {
	ctx, span := tracer.Start(ctx, "db.query",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
			attribute.String("db.sql.table", "users"),
		),
	)
	defer span.End()

	rows, err := db.QueryContext(ctx, "SELECT id, name, email, created_at FROM users ORDER BY id")
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	defer rows.Close()

	users := []User{}
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
			continue
		}
		users = append(users, u)
	}
	span.SetAttributes(attribute.Int("db.result_count", len(users)))
	json.NewEncoder(w).Encode(users)
}

func getUser(ctx context.Context, w http.ResponseWriter, idStr string) {
	ctx, span := tracer.Start(ctx, "db.query",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
			attribute.String("db.sql.table", "users"),
		),
	)
	defer span.End()

	var user User
	err := db.QueryRowContext(ctx, "SELECT id, name, email, created_at FROM users WHERE id = $1", idStr).
		Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err == sql.ErrNoRows {
		span.SetAttributes(attribute.Bool("db.not_found", true))
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
		return
	}
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	json.NewEncoder(w).Encode(user)
}

func createUser(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON"})
		return
	}
	if input.Name == "" || input.Email == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "name and email required"})
		return
	}

	ctx, span := tracer.Start(ctx, "db.query",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "INSERT"),
			attribute.String("db.sql.table", "users"),
		),
	)
	defer span.End()

	var user User
	err := db.QueryRowContext(ctx,
		"INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
		input.Name, input.Email,
	).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]string{"error": fmt.Sprintf("could not create user: %v", err)})
		return
	}
	span.SetAttributes(attribute.Int("db.user_id", user.ID))
	slog.InfoContext(ctx, "user created", "user_id", user.ID, "email", user.Email)
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(user)
}

func updateUser(ctx context.Context, w http.ResponseWriter, r *http.Request, idStr string) {
	var input struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON"})
		return
	}
	if input.Name == "" || input.Email == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "name and email required"})
		return
	}

	ctx, span := tracer.Start(ctx, "db.query",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "UPDATE"),
			attribute.String("db.sql.table", "users"),
		),
	)
	defer span.End()

	var user User
	err := db.QueryRowContext(ctx,
		"UPDATE users SET name = $1, email = $2 WHERE id = $3 RETURNING id, name, email, created_at",
		input.Name, input.Email, idStr,
	).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err == sql.ErrNoRows {
		span.SetAttributes(attribute.Bool("db.not_found", true))
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
		return
	}
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]string{"error": fmt.Sprintf("could not update user: %v", err)})
		return
	}
	slog.InfoContext(ctx, "user updated", "user_id", user.ID)
	json.NewEncoder(w).Encode(user)
}

func deleteUser(ctx context.Context, w http.ResponseWriter, idStr string) {
	ctx, span := tracer.Start(ctx, "db.query",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "DELETE"),
			attribute.String("db.sql.table", "users"),
		),
	)
	defer span.End()

	result, err := db.ExecContext(ctx, "DELETE FROM users WHERE id = $1", idStr)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		span.SetAttributes(attribute.Bool("db.not_found", true))
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
		return
	}
	slog.InfoContext(ctx, "user deleted", "user_id", idStr)
	json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	// Serve embedded HTML UI
	html, err := staticFS.ReadFile("static/index.html")
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"service": "platform-api",
			"version": Version,
		})
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(html)
}
