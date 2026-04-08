global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: app-node
    static_configs:
      - targets: ['__APP_PUBLIC_IP__:9100']

  - job_name: app-spring
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['__APP_PUBLIC_IP__:8080']
