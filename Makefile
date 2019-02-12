BUILDER_NAME            = aports-builder
ALPINE_VERSION          = 3.7
S3_APK_REPO_BUCKET_URI ?= s3://localhost
REPOSITORY              = backports ros/kinetic
APK_REPO_PRIVATE_KEY   ?= # path to your private key

ifeq ($(shell if [ -f "${APK_REPO_PRIVATE_KEY}" ]; then echo true; fi), true)
	PRIVATE_KEY_OPT = -v $(APK_REPO_PRIVATE_KEY):/home/builder/.abuild/builder@alpine-ros-experimental.rsa:ro
endif

.PHONY: build-builder
build-builder:
	docker build -t $(BUILDER_NAME):$(ALPINE_VERSION) .

.PHONY: $(REPOSITORY)
$(REPOSITORY):
	if [ ! -d packages/v$(ALPINE_VERSION)/$@ ]; then \
		mkdir -p packages/v$(ALPINE_VERSION)/$@; \
		chmod og+rwx packages/v$(ALPINE_VERSION)/$@; \
	fi
	docker run --rm -it \
		-v `pwd`:/src \
		-v `pwd`/packages/v$(ALPINE_VERSION):/home/builder/packages \
		$(PRIVATE_KEY_OPT) \
		$(BUILDER_NAME):$(ALPINE_VERSION) $@

.PHONY: s3-pull
s3-pull:
	aws s3 sync --no-sign-request $(S3_APK_REPO_BUCKET_URI)/v$(ALPINE_VERSION) packages/v$(ALPINE_VERSION)
	chmod -Rf og+rw packages/v$(ALPINE_VERSION) || true

.PHONY: s3-push
s3-push:
	aws s3 sync --acl=public-read packages/v$(ALPINE_VERSION) $(S3_APK_REPO_BUCKET_URI)/v$(ALPINE_VERSION)

.PHONY: all
all:
	$(MAKE) s3-pull
	$(MAKE) build-builder
	$(MAKE) $(REPOSITORY)