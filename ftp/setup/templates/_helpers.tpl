{{- define "ftp.loadBalancerAddr" -}}
{{- with (lookup "v1" "Service" .Release.Namespace "vsftpd") -}}
{{- first (index .status.loadBalancer.ingress 0 | pluck "hostname") -}}
{{- end -}}
{{- end -}}