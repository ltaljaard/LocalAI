GOCMD=go
GOTEST=$(GOCMD) test
GOVET=$(GOCMD) vet
BINARY_NAME=local-ai

ONNX_VERSION?=1.20.0
ONNX_ARCH?=x64
ONNX_OS?=linux

ONEAPI_VERSION?=2025.2

export BUILD_TYPE?=

GO_TAGS?=
BUILD_ID?=
NATIVE?=false

TEST_DIR=/tmp/test

TEST_FLAKES?=5

RANDOM := $(shell bash -c 'echo $$RANDOM')

VERSION?=$(shell git describe --always --tags || echo "dev" )
# go tool nm ./local-ai | grep Commit
LD_FLAGS?=-s -w
override LD_FLAGS += -X "github.com/mudler/LocalAI/internal.Version=$(VERSION)"
override LD_FLAGS += -X "github.com/mudler/LocalAI/internal.Commit=$(shell git rev-parse HEAD)"

OPTIONAL_TARGETS?=

export OS := $(shell uname -s)
ARCH := $(shell uname -m)
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
CYAN   := $(shell tput -Txterm setaf 6)
RESET  := $(shell tput -Txterm sgr0)

UPX?=
# check if upx exists
ifeq (, $(shell which upx))
	UPX=
else
	UPX=$(shell which upx)
endif

# Default Docker bridge IP
E2E_BRIDGE_IP?=172.17.0.1

ifndef UNAME_S
UNAME_S := $(shell uname -s)
endif
# Detect if we are running on arm64
ifneq (,$(findstring aarch64,$(shell uname -m)))
	ONNX_ARCH=aarch64
endif

ifeq ($(OS),Darwin)
	ONNX_OS=osx
	ifneq (,$(findstring aarch64,$(shell uname -m)))
		ONNX_ARCH=arm64
	else ifneq (,$(findstring arm64,$(shell uname -m)))
		ONNX_ARCH=arm64
	else
		ONNX_ARCH=x86_64
	endif

	ifeq ($(OSX_SIGNING_IDENTITY),)
		OSX_SIGNING_IDENTITY := $(shell security find-identity -v -p codesigning | grep '"' | head -n 1 | sed -E 's/.*"(.*)"/\1/')
	endif
endif

ALL_GRPC_BACKENDS=backend-assets/grpc/huggingface
ALL_GRPC_BACKENDS+=backend-assets/grpc/local-store
ALL_GRPC_BACKENDS+=backend-assets/grpc/silero-vad
ALL_GRPC_BACKENDS+=$(OPTIONAL_GRPC)
# Use filter-out to remove the specified backends
ALL_GRPC_BACKENDS := $(filter-out $(SKIP_GRPC_BACKEND),$(ALL_GRPC_BACKENDS))

GRPC_BACKENDS?=$(ALL_GRPC_BACKENDS) $(OPTIONAL_GRPC)
TEST_PATHS?=./api/... ./pkg/... ./core/...

# If empty, then we build all
ifeq ($(GRPC_BACKENDS),)
	GRPC_BACKENDS=$(ALL_GRPC_BACKENDS)
endif

ifeq ($(BUILD_API_ONLY),true)
	GRPC_BACKENDS=
endif

.PHONY: all test build vendor

all: help

sources/onnxruntime:
	mkdir -p sources/onnxruntime
	curl -L https://github.com/microsoft/onnxruntime/releases/download/v$(ONNX_VERSION)/onnxruntime-$(ONNX_OS)-$(ONNX_ARCH)-$(ONNX_VERSION).tgz -o sources/onnxruntime/onnxruntime-$(ONNX_OS)-$(ONNX_ARCH)-$(ONNX_VERSION).tgz
	cd sources/onnxruntime && tar -xvf onnxruntime-$(ONNX_OS)-$(ONNX_ARCH)-$(ONNX_VERSION).tgz && rm onnxruntime-$(ONNX_OS)-$(ONNX_ARCH)-$(ONNX_VERSION).tgz
	cd sources/onnxruntime && mv onnxruntime-$(ONNX_OS)-$(ONNX_ARCH)-$(ONNX_VERSION)/* ./

backend-assets/lib/libonnxruntime.so.1: backend-assets/lib sources/onnxruntime
	cp -rfv sources/onnxruntime/lib/* backend-assets/lib/
ifeq ($(OS),Darwin)
	mv backend-assets/lib/libonnxruntime.$(ONNX_VERSION).dylib backend-assets/lib/libonnxruntime.dylib
else
	mv backend-assets/lib/libonnxruntime.so.$(ONNX_VERSION) backend-assets/lib/libonnxruntime.so.1
endif

## GENERIC
rebuild: ## Rebuilds the project
	$(GOCMD) clean -cache
	$(MAKE) build

clean: ## Remove build related file
	$(GOCMD) clean -cache
	rm -f prepare
	rm -rf $(BINARY_NAME)
	rm -rf release/
	rm -rf backend-assets/*
	$(MAKE) -C backend/cpp/grpc clean
	$(MAKE) protogen-clean
	rmdir pkg/grpc/proto || true

clean-tests:
	rm -rf test-models
	rm -rf test-dir
	rm -rf core/http/backend-assets

clean-dc: clean
	cp -r /build/backend-assets /workspace/backend-assets

## Install Go tools
install-go-tools:
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@1958fcbe2ca8bd93af633f11e97d44e567e945af
	go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2
	go install github.com/GeertJohan/go.rice/rice@latest

## Build:
build: backend-assets grpcs install-go-tools ## Build the project
	$(info ${GREEN}I local-ai build info:${RESET})
	$(info ${GREEN}I BUILD_TYPE: ${YELLOW}$(BUILD_TYPE)${RESET})
	$(info ${GREEN}I GO_TAGS: ${YELLOW}$(GO_TAGS)${RESET})
	$(info ${GREEN}I LD_FLAGS: ${YELLOW}$(LD_FLAGS)${RESET})
	$(info ${GREEN}I UPX: ${YELLOW}$(UPX)${RESET})
ifneq ($(BACKEND_LIBS),)
	$(MAKE) backend-assets/lib
	cp -f $(BACKEND_LIBS) backend-assets/lib/
endif
	rm -rf $(BINARY_NAME) || true
	CGO_LDFLAGS="$(CGO_LDFLAGS)" $(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o $(BINARY_NAME) ./
	rice append --exec $(BINARY_NAME)

build-api:
	BUILD_GRPC_FOR_BACKEND_LLAMA=true BUILD_API_ONLY=true GO_TAGS=p2p $(MAKE) build

backend-assets/lib:
	mkdir -p backend-assets/lib

dist:
	GO_TAGS="p2p" $(MAKE) build
	GO_TAGS="p2p" STATIC=true $(MAKE) build
	mkdir -p release
# if BUILD_ID is empty, then we don't append it to the binary name
ifeq ($(BUILD_ID),)
	cp $(BINARY_NAME) release/$(BINARY_NAME)-$(OS)-$(ARCH)
	shasum -a 256 release/$(BINARY_NAME)-$(OS)-$(ARCH) > release/$(BINARY_NAME)-$(OS)-$(ARCH).sha256
else
	cp $(BINARY_NAME) release/$(BINARY_NAME)-$(BUILD_ID)-$(OS)-$(ARCH)
	shasum -a 256 release/$(BINARY_NAME)-$(BUILD_ID)-$(OS)-$(ARCH) > release/$(BINARY_NAME)-$(BUILD_ID)-$(OS)-$(ARCH).sha256
endif

osx-signed: build
	codesign --deep --force --sign "$(OSX_SIGNING_IDENTITY)" --entitlements "./Entitlements.plist" "./$(BINARY_NAME)"

## Run
run: ## run local-ai
	CGO_LDFLAGS="$(CGO_LDFLAGS)" $(GOCMD) run ./

test-models/testmodel.ggml:
	mkdir test-models
	mkdir test-dir
	wget -q https://huggingface.co/mradermacher/gpt2-alpaca-gpt4-GGUF/resolve/main/gpt2-alpaca-gpt4.Q4_K_M.gguf -O test-models/testmodel.ggml
	wget -q https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin -O test-models/whisper-en
	wget -q https://huggingface.co/mudler/all-MiniLM-L6-v2/resolve/main/ggml-model-q4_0.bin -O test-models/bert
	wget -q https://cdn.openai.com/whisper/draft-20220913a/micro-machines.wav -O test-dir/audio.wav
	cp tests/models_fixtures/* test-models

prepare-test: grpcs
	cp -rf backend-assets core/http
	cp tests/models_fixtures/* test-models

########################################################
## Tests
########################################################

## Test targets
test: test-models/testmodel.ggml grpcs
	@echo 'Running tests'
	export GO_TAGS="debug"
	$(MAKE) prepare-test
	HUGGINGFACE_GRPC=$(abspath ./)/backend/python/transformers/run.sh TEST_DIR=$(abspath ./)/test-dir/ FIXTURES=$(abspath ./)/tests/fixtures CONFIG_FILE=$(abspath ./)/test-models/config.yaml MODELS_PATH=$(abspath ./)/test-models BACKENDS_PATH=$(abspath ./)/backends \
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --label-filter="!llama-gguf"  --flake-attempts $(TEST_FLAKES) --fail-fast -v -r $(TEST_PATHS)
	$(MAKE) test-llama-gguf
	$(MAKE) test-tts
	$(MAKE) test-stablediffusion

backends/llama-cpp: docker-build-llama-cpp docker-save-llama-cpp build-api
	./local-ai backends install "ocifile://$(abspath ./backend-images/llama-cpp.tar)"

backends/piper: docker-build-piper docker-save-piper build-api
	./local-ai backends install "ocifile://$(abspath ./backend-images/piper.tar)"

backends/stablediffusion-ggml: docker-build-stablediffusion-ggml docker-save-stablediffusion-ggml build-api
	./local-ai backends install "ocifile://$(abspath ./backend-images/stablediffusion-ggml.tar)"

backends/whisper: docker-build-whisper docker-save-whisper build-api
	./local-ai backends install "ocifile://$(abspath ./backend-images/whisper.tar)"

########################################################
## AIO tests
########################################################

docker-build-aio:
	docker build --build-arg MAKEFLAGS="--jobs=5 --output-sync=target" -t local-ai:tests -f Dockerfile .
	BASE_IMAGE=local-ai:tests DOCKER_AIO_IMAGE=local-ai-aio:test $(MAKE) docker-aio

e2e-aio:
	LOCALAI_BACKEND_DIR=$(abspath ./backends) \
	LOCALAI_MODELS_DIR=$(abspath ./models) \
	LOCALAI_IMAGE_TAG=test \
	LOCALAI_IMAGE=local-ai-aio \
	$(MAKE) run-e2e-aio

run-e2e-aio: protogen-go
	@echo 'Running e2e AIO tests'
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --flake-attempts $(TEST_FLAKES) -v -r ./tests/e2e-aio

########################################################
## E2E tests
########################################################

prepare-e2e:
	mkdir -p $(TEST_DIR)
	cp -rfv $(abspath ./tests/e2e-fixtures)/gpu.yaml $(TEST_DIR)/gpu.yaml
	test -e $(TEST_DIR)/ggllm-test-model.bin || wget -q https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q2_K.gguf -O $(TEST_DIR)/ggllm-test-model.bin
	docker build --build-arg GRPC_BACKENDS="$(GRPC_BACKENDS)" --build-arg IMAGE_TYPE=core --build-arg BUILD_TYPE=$(BUILD_TYPE) --build-arg CUDA_MAJOR_VERSION=12 --build-arg CUDA_MINOR_VERSION=0 --build-arg FFMPEG=true -t localai-tests .

run-e2e-image:
	ls -liah $(abspath ./tests/e2e-fixtures)
	docker run -p 5390:8080 -e MODELS_PATH=/models -e THREADS=1 -e DEBUG=true -d --rm -v $(TEST_DIR):/models --gpus all --name e2e-tests-$(RANDOM) localai-tests

test-e2e:
	@echo 'Running e2e tests'
	BUILD_TYPE=$(BUILD_TYPE) \
	LOCALAI_API=http://$(E2E_BRIDGE_IP):5390/v1 \
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --flake-attempts $(TEST_FLAKES) -v -r ./tests/e2e

teardown-e2e:
	rm -rf $(TEST_DIR) || true
	docker stop $$(docker ps -q --filter ancestor=localai-tests)

########################################################
## Integration and unit tests
########################################################

test-llama-gguf: prepare-test
	TEST_DIR=$(abspath ./)/test-dir/ FIXTURES=$(abspath ./)/tests/fixtures CONFIG_FILE=$(abspath ./)/test-models/config.yaml MODELS_PATH=$(abspath ./)/test-models BACKENDS_PATH=$(abspath ./)/backends \
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --label-filter="llama-gguf" --flake-attempts $(TEST_FLAKES) -v -r $(TEST_PATHS)

test-tts: prepare-test
	TEST_DIR=$(abspath ./)/test-dir/ FIXTURES=$(abspath ./)/tests/fixtures CONFIG_FILE=$(abspath ./)/test-models/config.yaml MODELS_PATH=$(abspath ./)/test-models BACKENDS_PATH=$(abspath ./)/backends \
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --label-filter="tts" --flake-attempts $(TEST_FLAKES) -v -r $(TEST_PATHS)

test-stablediffusion: prepare-test
	TEST_DIR=$(abspath ./)/test-dir/ FIXTURES=$(abspath ./)/tests/fixtures CONFIG_FILE=$(abspath ./)/test-models/config.yaml MODELS_PATH=$(abspath ./)/test-models BACKENDS_PATH=$(abspath ./)/backends \
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --label-filter="stablediffusion" --flake-attempts $(TEST_FLAKES) -v -r $(TEST_PATHS)

test-stores: backend-assets/grpc/local-store
	mkdir -p tests/integration/backend-assets/grpc
	cp -f backend-assets/grpc/local-store tests/integration/backend-assets/grpc/
	$(GOCMD) run github.com/onsi/ginkgo/v2/ginkgo --label-filter="stores" --flake-attempts $(TEST_FLAKES) -v -r tests/integration

test-container:
	docker build --target requirements -t local-ai-test-container .
	docker run -ti --rm --entrypoint /bin/bash -ti -v $(abspath ./):/build local-ai-test-container

########################################################
## Help
########################################################

## Help:
help: ## Show this help.
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) {printf "    ${YELLOW}%-20s${GREEN}%s${RESET}\n", $$1, $$2} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)

########################################################
## Backends
########################################################

.PHONY: protogen
protogen: protogen-go protogen-python

.PHONY: protogen-clean
protogen-clean: protogen-go-clean protogen-python-clean

.PHONY: protogen-go
protogen-go: install-go-tools
	mkdir -p pkg/grpc/proto
	protoc --experimental_allow_proto3_optional -Ibackend/ --go_out=pkg/grpc/proto/ --go_opt=paths=source_relative --go-grpc_out=pkg/grpc/proto/ --go-grpc_opt=paths=source_relative \
    backend/backend.proto

.PHONY: protogen-go-clean
protogen-go-clean:
	$(RM) pkg/grpc/proto/backend.pb.go pkg/grpc/proto/backend_grpc.pb.go
	$(RM) bin/*

.PHONY: protogen-python
protogen-python: bark-protogen coqui-protogen chatterbox-protogen diffusers-protogen exllama2-protogen rerankers-protogen transformers-protogen kokoro-protogen vllm-protogen faster-whisper-protogen

.PHONY: protogen-python-clean
protogen-python-clean: bark-protogen-clean coqui-protogen-clean chatterbox-protogen-clean diffusers-protogen-clean  exllama2-protogen-clean rerankers-protogen-clean transformers-protogen-clean kokoro-protogen-clean vllm-protogen-clean faster-whisper-protogen-clean

.PHONY: bark-protogen
bark-protogen:
	$(MAKE) -C backend/python/bark protogen

.PHONY: bark-protogen-clean
bark-protogen-clean:
	$(MAKE) -C backend/python/bark protogen-clean

.PHONY: coqui-protogen
coqui-protogen:
	$(MAKE) -C backend/python/coqui protogen

.PHONY: coqui-protogen-clean
coqui-protogen-clean:
	$(MAKE) -C backend/python/coqui protogen-clean

.PHONY: diffusers-protogen
diffusers-protogen:
	$(MAKE) -C backend/python/diffusers protogen

.PHONY: chatterbox-protogen
chatterbox-protogen:
	$(MAKE) -C backend/python/chatterbox protogen

.PHONY: diffusers-protogen-clean
diffusers-protogen-clean:
	$(MAKE) -C backend/python/diffusers protogen-clean

.PHONY: chatterbox-protogen-clean
chatterbox-protogen-clean:
	$(MAKE) -C backend/python/chatterbox protogen-clean

.PHONY: faster-whisper-protogen
faster-whisper-protogen:
	$(MAKE) -C backend/python/faster-whisper protogen

.PHONY: faster-whisper-protogen-clean
faster-whisper-protogen-clean:
	$(MAKE) -C backend/python/faster-whisper protogen-clean

.PHONY: exllama2-protogen
exllama2-protogen:
	$(MAKE) -C backend/python/exllama2 protogen

.PHONY: exllama2-protogen-clean
exllama2-protogen-clean:
	$(MAKE) -C backend/python/exllama2 protogen-clean

.PHONY: rerankers-protogen
rerankers-protogen:
	$(MAKE) -C backend/python/rerankers protogen

.PHONY: rerankers-protogen-clean
rerankers-protogen-clean:
	$(MAKE) -C backend/python/rerankers protogen-clean

.PHONY: transformers-protogen
transformers-protogen:
	$(MAKE) -C backend/python/transformers protogen

.PHONY: transformers-protogen-clean
transformers-protogen-clean:
	$(MAKE) -C backend/python/transformers protogen-clean

.PHONY: kokoro-protogen
kokoro-protogen:
	$(MAKE) -C backend/python/kokoro protogen

.PHONY: kokoro-protogen-clean
kokoro-protogen-clean:
	$(MAKE) -C backend/python/kokoro protogen-clean

.PHONY: vllm-protogen
vllm-protogen:
	$(MAKE) -C backend/python/vllm protogen

.PHONY: vllm-protogen-clean
vllm-protogen-clean:
	$(MAKE) -C backend/python/vllm protogen-clean

## GRPC
# Note: it is duplicated in the Dockerfile
prepare-extra-conda-environments: protogen-python
	$(MAKE) -C backend/python/bark
	$(MAKE) -C backend/python/coqui
	$(MAKE) -C backend/python/diffusers
	$(MAKE) -C backend/python/chatterbox
	$(MAKE) -C backend/python/faster-whisper
	$(MAKE) -C backend/python/vllm
	$(MAKE) -C backend/python/rerankers
	$(MAKE) -C backend/python/transformers
	$(MAKE) -C backend/python/kokoro
	$(MAKE) -C backend/python/exllama2

prepare-test-extra: protogen-python
	$(MAKE) -C backend/python/transformers
	$(MAKE) -C backend/python/diffusers
	$(MAKE) -C backend/python/chatterbox
	$(MAKE) -C backend/python/vllm

test-extra: prepare-test-extra
	$(MAKE) -C backend/python/transformers test
	$(MAKE) -C backend/python/diffusers test
	$(MAKE) -C backend/python/chatterbox test
	$(MAKE) -C backend/python/vllm test

backend-assets:
	mkdir -p backend-assets
ifeq ($(BUILD_API_ONLY),true)
	touch backend-assets/keep
endif


backend-assets/grpc:
	mkdir -p backend-assets/grpc

backend-assets/grpc/huggingface: protogen-go backend-assets/grpc
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/huggingface ./backend/go/llm/langchain/
ifneq ($(UPX),)
	$(UPX) backend-assets/grpc/huggingface
endif

backend-assets/grpc/silero-vad: protogen-go backend-assets/grpc backend-assets/lib/libonnxruntime.so.1
	CGO_LDFLAGS="$(CGO_LDFLAGS)" CPATH="$(CPATH):$(CURDIR)/sources/onnxruntime/include/" LIBRARY_PATH=$(CURDIR)/backend-assets/lib \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/silero-vad ./backend/go/vad/silero
ifneq ($(UPX),)
	$(UPX) backend-assets/grpc/silero-vad
endif

backend-assets/grpc/local-store: backend-assets/grpc protogen-go
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/local-store ./backend/go/stores/
ifneq ($(UPX),)
	$(UPX) backend-assets/grpc/local-store
endif

grpcs: protogen-go $(GRPC_BACKENDS)

DOCKER_IMAGE?=local-ai
DOCKER_AIO_IMAGE?=local-ai-aio
IMAGE_TYPE?=core
BASE_IMAGE?=ubuntu:22.04

docker:
	docker build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg IMAGE_TYPE=$(IMAGE_TYPE) \
		--build-arg GO_TAGS="$(GO_TAGS)" \
		--build-arg MAKEFLAGS="$(DOCKER_MAKEFLAGS)" \
		--build-arg BUILD_TYPE=$(BUILD_TYPE) \
		-t $(DOCKER_IMAGE) .

docker-cuda11:
	docker build \
		--build-arg CUDA_MAJOR_VERSION=11 \
		--build-arg CUDA_MINOR_VERSION=8 \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg IMAGE_TYPE=$(IMAGE_TYPE) \
		--build-arg GO_TAGS="$(GO_TAGS)" \
		--build-arg MAKEFLAGS="$(DOCKER_MAKEFLAGS)" \
		--build-arg BUILD_TYPE=$(BUILD_TYPE) \
		-t $(DOCKER_IMAGE)-cuda11 .

docker-aio:
	@echo "Building AIO image with base $(BASE_IMAGE) as $(DOCKER_AIO_IMAGE)"
	docker build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg MAKEFLAGS="$(DOCKER_MAKEFLAGS)" \
		-t $(DOCKER_AIO_IMAGE) -f Dockerfile.aio .

docker-aio-all:
	$(MAKE) docker-aio DOCKER_AIO_SIZE=cpu
	$(MAKE) docker-aio DOCKER_AIO_SIZE=cpu

docker-image-intel:
	docker build \
		--build-arg BASE_IMAGE=intel/oneapi-basekit:${ONEAPI_VERSION}.0-0-devel-ubuntu24.04 \
		--build-arg IMAGE_TYPE=$(IMAGE_TYPE) \
		--build-arg GO_TAGS="$(GO_TAGS)" \
		--build-arg MAKEFLAGS="$(DOCKER_MAKEFLAGS)" \
		--build-arg GRPC_BACKENDS="$(GRPC_BACKENDS)" \
		--build-arg BUILD_TYPE=sycl_f32 -t $(DOCKER_IMAGE) .

docker-image-intel-xpu:
	docker build \
		--build-arg BASE_IMAGE=intel/oneapi-basekit:${ONEAPI_VERSION}.0-0-devel-ubuntu22.04 \
		--build-arg IMAGE_TYPE=$(IMAGE_TYPE) \
		--build-arg GO_TAGS="$(GO_TAGS)" \
		--build-arg MAKEFLAGS="$(DOCKER_MAKEFLAGS)" \
		--build-arg GRPC_BACKENDS="$(GRPC_BACKENDS)" \
		--build-arg BUILD_TYPE=sycl_f32 -t $(DOCKER_IMAGE) .

########################################################
## Backends
########################################################

backend-images:
	mkdir -p backend-images

docker-build-llama-cpp:
	docker build --build-arg BUILD_TYPE=$(BUILD_TYPE) --build-arg IMAGE_BASE=$(IMAGE_BASE) -t local-ai-backend:llama-cpp -f backend/Dockerfile.llama-cpp .

docker-build-bark-cpp:
	docker build -t local-ai-backend:bark-cpp -f backend/Dockerfile.go --build-arg BACKEND=bark-cpp .

docker-build-piper:
	docker build -t local-ai-backend:piper -f backend/Dockerfile.go --build-arg BACKEND=piper .

docker-save-piper: backend-images
	docker save local-ai-backend:piper -o backend-images/piper.tar

docker-save-llama-cpp: backend-images
	docker save local-ai-backend:llama-cpp -o backend-images/llama-cpp.tar

docker-save-bark-cpp: backend-images
	docker save local-ai-backend:bark-cpp -o backend-images/bark-cpp.tar

docker-build-stablediffusion-ggml:
	docker build -t local-ai-backend:stablediffusion-ggml -f backend/Dockerfile.go --build-arg BACKEND=stablediffusion-ggml .

docker-save-stablediffusion-ggml: backend-images
	docker save local-ai-backend:stablediffusion-ggml -o backend-images/stablediffusion-ggml.tar

docker-build-rerankers:
	docker build -t local-ai-backend:rerankers -f backend/Dockerfile.python --build-arg BACKEND=rerankers .

docker-build-vllm:
	docker build -t local-ai-backend:vllm -f backend/Dockerfile.python --build-arg BACKEND=vllm .

docker-build-transformers:
	docker build -t local-ai-backend:transformers -f backend/Dockerfile.python --build-arg BACKEND=transformers .

docker-build-diffusers:
	docker build -t local-ai-backend:diffusers -f backend/Dockerfile.python --build-arg BACKEND=diffusers .

docker-build-kokoro:
	docker build -t local-ai-backend:kokoro -f backend/Dockerfile.python --build-arg BACKEND=kokoro .

docker-build-whisper:
	docker build --build-arg BUILD_TYPE=$(BUILD_TYPE) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t local-ai-backend:whisper -f backend/Dockerfile.go --build-arg BACKEND=whisper  .

docker-save-whisper: backend-images
	docker save local-ai-backend:whisper -o backend-images/whisper.tar

docker-build-faster-whisper:
	docker build -t local-ai-backend:faster-whisper -f backend/Dockerfile.python --build-arg BACKEND=faster-whisper .

docker-build-coqui:
	docker build -t local-ai-backend:coqui -f backend/Dockerfile.python --build-arg BACKEND=coqui .

docker-build-bark:
	docker build -t local-ai-backend:bark -f backend/Dockerfile.python --build-arg BACKEND=bark .

docker-build-chatterbox:
	docker build -t local-ai-backend:chatterbox -f backend/Dockerfile.python --build-arg BACKEND=chatterbox .

docker-build-exllama2:
	docker build -t local-ai-backend:exllama2 -f backend/Dockerfile.python --build-arg BACKEND=exllama2 .

docker-build-backends: docker-build-llama-cpp docker-build-rerankers docker-build-vllm docker-build-transformers docker-build-diffusers docker-build-kokoro docker-build-faster-whisper docker-build-coqui docker-build-bark docker-build-chatterbox docker-build-exllama2

########################################################
### END Backends
########################################################

.PHONY: swagger
swagger:
	swag init -g core/http/app.go --output swagger

.PHONY: gen-assets
gen-assets:
	$(GOCMD) run core/dependencies_manager/manager.go webui_static.yaml core/http/static/assets

## Documentation
docs/layouts/_default:
	mkdir -p docs/layouts/_default

docs/static/gallery.html: docs/layouts/_default
	$(GOCMD) run ./.github/ci/modelslist.go ./gallery/index.yaml > docs/static/gallery.html

docs/public: docs/layouts/_default docs/static/gallery.html
	cd docs && hugo --minify

docs-clean:
	rm -rf docs/public
	rm -rf docs/static/gallery.html

.PHONY: docs
docs: docs/static/gallery.html
	cd docs && hugo serve
