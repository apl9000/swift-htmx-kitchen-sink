
.PHONY: dev 
dev: ## Start the full dev environment (Vapor in docker, tailwind and livereload locally)
	( $(MAKE) tailwind ) &
	( $(MAKE) livereload ) &
	docker compose up app

.PHONY: app
app: ## Start the Vapor app in docker
	docker compose up --build -d

.PHONY: tailwind
tailwind: ## Start the tailwind watcher
	npx tailwindcss -i ./Public/app.css -o ./Public/styles.css --watch

.PHONY: livereload
livereload: ## Start the livereload server
	npx livereload ./Public --port 35730 || true

.PHONY: install
install: ## Install all dependencies
	npm install

.PHONY: 
clean:
	docker compose down -v --remove-orphans
	rm -rf node_modules package-lock.json ./Public/styles.css

.PHONY: stop
stop:
	@echo "Killing LiveReload on port 35730 if running..."
	@lsof -t -i :35730 | xargs kill -9 || true
	docker compose down --remove-orphans