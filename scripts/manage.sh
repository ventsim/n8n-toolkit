#!/usr/bin/env bash
case "$1" in
  start) docker compose up -d ;;
  stop) docker compose down ;;
  restart) docker compose restart ;;
  logs) docker compose logs -f ;;
  status) docker compose ps ;;
  shell) docker compose exec n8n sh ;;
  *) echo "Usage: $0 {start|stop|restart|logs|status|shell}" ;;
esac
