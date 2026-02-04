.PHONY: build run stop logs shell clean rebuild

IMAGE_NAME := nas-manager
CONTAINER_NAME := nas-manager
PORT := 9000

build:
	docker build -t $(IMAGE_NAME) .

run:
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p $(PORT):9000 \
		-v $(PWD)/scripts:/scripts:ro \
		-v nas-manager-data:/var/lib/dyndns \
		$(IMAGE_NAME)

stop:
	docker stop $(CONTAINER_NAME) || true
	docker rm $(CONTAINER_NAME) || true

logs:
	docker logs -f $(CONTAINER_NAME)

shell:
	docker exec -it $(CONTAINER_NAME) /bin/sh

clean: stop
	docker rmi $(IMAGE_NAME) || true
	docker volume rm nas-manager-data || true

rebuild: stop build run

test:
	curl -s "http://localhost:$(PORT)/hooks/fritzbox-dyndns-update?domain=test.example.com&ipaddr=1.2.3.4"
