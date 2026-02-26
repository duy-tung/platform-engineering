{{/*
Common labels
*/}}
{{- define "platform-api.labels" -}}
app: {{ .Chart.Name }}
version: {{ .Values.image.tag | quote }}
managed-by: helm
{{- end }}

{{/*
Selector labels
*/}}
{{- define "platform-api.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Database URL
*/}}
{{- define "platform-api.databaseUrl" -}}
postgres://{{ .Values.postgres.credentials.user }}:{{ .Values.postgres.credentials.password }}@postgres:5432/{{ .Values.postgres.credentials.database }}?sslmode=disable
{{- end }}
