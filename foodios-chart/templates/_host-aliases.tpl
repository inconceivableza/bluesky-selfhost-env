{{/*
Generate hostAliases for inter-service HTTPS communication
Services need to resolve FQDNs to Traefik ingress instead of localhost
Uses lookup to dynamically get Traefik cluster IP
*/}}
{{- define "foodios.hostAliases" -}}
{{- if .Values.global.developmentMode }}
{{- $traefikSvc := lookup "v1" "Service" "kube-system" "traefik" }}
{{- if $traefikSvc }}
hostAliases:
- ip: "{{ $traefikSvc.spec.clusterIP }}"
  hostnames:
  - "{{ .Values.fqdns.api }}"
  - "{{ .Values.fqdns.bgs }}"
  - "{{ .Values.fqdns.bsky }}"
  - "{{ .Values.fqdns.card }}"
  - "{{ .Values.fqdns.embed }}"
  - "{{ .Values.fqdns.feedgen }}"
  - "{{ .Values.fqdns.ip }}"
  - "{{ .Values.fqdns.jetstream }}"
  - "{{ .Values.fqdns.link }}"
  - "{{ .Values.fqdns.logs }}"
  - "{{ .Values.fqdns.ozone }}"
  - "{{ .Values.fqdns.palomar }}"
  - "{{ .Values.fqdns.pds }}"
  - "{{ .Values.fqdns.plc }}"
  - "{{ .Values.fqdns.publicApi }}"
  - "{{ .Values.fqdns.relay }}"
  - "{{ .Values.fqdns.socialapp }}"
{{- end }}
{{- end }}
{{- end }}
