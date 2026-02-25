.PHONY: run stop logs shell clean

IMAGE_NAME := almir/webhook:latest
CONTAINER_NAME := nas-manager
PORT := 9000

run:
	docker run -d \
		--name $(CONTAINER_NAME) \
		--user 0:0 \
		-p $(PORT):9000 \
		-v $(PWD)/webhook:/etc/webhook:ro \
		-v $(PWD)/scripts:/scripts:ro \
		-v nas-manager-data:/var/lib/dyndns \
		$(IMAGE_NAME) \
		/bin/sh -ec 'exec /usr/local/bin/webhook -verbose -hooks=/etc/webhook/hooks.json -hotreload'

stop:
	docker stop $(CONTAINER_NAME) || true
	docker rm $(CONTAINER_NAME) || true

logs:
	docker logs -f $(CONTAINER_NAME)

shell:
	docker exec -it $(CONTAINER_NAME) /bin/sh

clean: stop
	docker volume rm nas-manager-data || true

test:
	curl -s "http://localhost:$(PORT)/hooks/fritzbox-dyndns-update?domain=test.example.com&ipaddr=1.2.3.4"
