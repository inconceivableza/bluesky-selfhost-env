{{/*
Expand the name of the chart.
*/}}
{{- define "foodios.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "foodios.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "foodios.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "foodios.labels" -}}
helm.sh/chart: {{ include "foodios.chart" . }}
{{ include "foodios.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "foodios.selectorLabels" -}}
app.kubernetes.io/name: {{ include "foodios.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create a standard ingress template
Usage: {{- include "foodios.ingress" (dict "name" "pds" "host" .Values.fqdns.pds "port" .Values.pds.port "root" .) }}
*/}}
{{- define "foodios.ingress" -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  namespace: {{ .root.Values.global.namespace }}
  labels:
    app: {{ .name }}
    {{- include "foodios.labels" .root | nindent 4 }}
  annotations:
    {{- if .root.Values.global.tls.enabled }}
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.tls.certresolver: "letsencrypt"
    {{- end }}
    {{- if .root.Values.global.developmentMode }}
    {{- with .root.Values.ingress.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- end }}
spec:
  ingressClassName: {{ .root.Values.ingress.className }}
  {{- if .root.Values.global.tls.enabled }}
  tls:
  - hosts:
    - {{ .host }}
    secretName: {{ .root.Values.global.tls.secretName | default (printf "%s-tls" .name) }}
  {{- end }}
  rules:
  - host: {{ .host }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ .service | default .name }}
            port:
              number: {{ .port }}
{{- end }}

{{/*
Create image name
Usage: {{ include "foodios.image" (dict "image" .Values.pds.image "tag" .Values.pds.tag "registry" .Values.global.imageRegistry) }}
*/}}
{{- define "foodios.image" -}}
{{- printf "%s/%s:%s" .registry .image .tag }}
{{- end }}
