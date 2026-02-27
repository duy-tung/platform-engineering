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
Database URL — switches based on database.mode
*/}}
{{- define "platform-api.databaseUrl" -}}
{{- if eq .Values.database.mode "cloudsql" -}}
postgres://{{ .Values.database.credentials.user }}:{{ .Values.database.credentials.password }}@127.0.0.1:{{ .Values.database.cloudsql.port }}/{{ .Values.database.credentials.database }}?sslmode=disable
{{- else -}}
postgres://{{ .Values.database.credentials.user }}:{{ .Values.database.credentials.password }}@postgres:5432/{{ .Values.database.credentials.database }}?sslmode=disable
{{- end -}}
{{- end }}
