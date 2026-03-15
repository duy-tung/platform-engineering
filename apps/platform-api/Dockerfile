# ---- Stage 1: Build ----
# Dùng golang image lớn (~800MB) để compile code
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy go.mod trước → Docker cache layer → không cần tải lại dependencies mỗi lần build
COPY go.mod go.sum ./
RUN go mod download

# Copy source code và build binary
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w -X main.Version=${VERSION}" \
    -o /platform-api .

# ---- Stage 2: Runtime ----
# Dùng scratch (image trống hoàn toàn, 0MB) → chỉ chứa binary
# → Image cuối cùng chỉ ~10MB thay vì ~800MB
FROM scratch

# Copy CA certificates (cần cho HTTPS connections)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary
COPY --from=builder /platform-api /platform-api

# Non-root user (security best practice)
USER 65534

EXPOSE 8080

ENTRYPOINT ["/platform-api"]
