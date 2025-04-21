+++
disableToc = false
title = "Quickstart"
weight = 3
url = '/basics/getting_started/'
icon = "rocket_launch"
+++

**LocalAI** is a free, open-source alternative to OpenAI (Anthropic, etc.), functioning as a drop-in replacement REST API for local inferencing. It allows you to run [LLMs]({{% relref "docs/features/text-generation" %}}), generate images, and produce audio, all locally or on-premises with consumer-grade hardware, supporting multiple model families and architectures.

{{% alert icon="💡" %}}

**Security considerations**

If you are exposing LocalAI remotely, make sure you protect the API endpoints adequately with a mechanism which allows to protect from the incoming traffic or alternatively, run LocalAI with `API_KEY` to gate the access with an API key. The API key guarantees a total access to the features (there is no role separation), and it is to be considered as likely as an admin role.

{{% /alert %}}

## Quickstart

### Using the Bash Installer

```bash
# Basic installation
curl https://localai.io/install.sh | sh
```

See [Installer]({{% relref "docs/advanced/installer" %}}) for all the supported options

### Run with docker:
```bash
# CPU only image:
docker run -ti --name local-ai -p 8080:8080 localai/localai:latest-cpu

# Nvidia GPU:
docker run -ti --name local-ai -p 8080:8080 --gpus all localai/localai:latest-gpu-nvidia-cuda-12

# CPU and GPU image (bigger size):
docker run -ti --name local-ai -p 8080:8080 localai/localai:latest

# AIO images (it will pre-download a set of models ready for use, see https://localai.io/basics/container/)
docker run -ti --name local-ai -p 8080:8080 localai/localai:latest-aio-cpu
```

### Load models:

```bash
# From the model gallery (see available models with `local-ai models list`, in the WebUI from the model tab, or visiting https://models.localai.io)
local-ai run llama-3.2-1b-instruct:q4_k_m
# Start LocalAI with the phi-2 model directly from huggingface
local-ai run huggingface://TheBloke/phi-2-GGUF/phi-2.Q8_0.gguf
# Install and run a model from the Ollama OCI registry
local-ai run ollama://gemma:2b
# Run a model from a configuration file
local-ai run https://gist.githubusercontent.com/.../phi-2.yaml
# Install and run a model from a standard OCI registry (e.g., Docker Hub)
local-ai run oci://localai/phi-2:latest
```


For a full list of options, refer to the [Installer Options]({{% relref "docs/advanced/installer" %}}) documentation.

Binaries can also be [manually downloaded]({{% relref "docs/reference/binaries" %}}).

## Using Homebrew on MacOS

{{% alert icon="⚠️" %}}
The Homebrew formula currently doesn't have the same options than the bash script
{{% /alert %}}

You can install Homebrew's [LocalAI](https://formulae.brew.sh/formula/localai) with the following command:

```
brew install localai
```


## Using Container Images or Kubernetes

LocalAI is available as a container image compatible with various container engines such as Docker, Podman, and Kubernetes. Container images are published on [quay.io](https://quay.io/repository/go-skynet/local-ai?tab=tags&tag=latest) and [Docker Hub](https://hub.docker.com/r/localai/localai).

For detailed instructions, see [Using container images]({{% relref "docs/getting-started/container-images" %}}). For Kubernetes deployment, see [Run with Kubernetes]({{% relref "docs/getting-started/kubernetes" %}}).

## Running LocalAI with All-in-One (AIO) Images

> _Already have a model file? Skip to [Run models manually]({{% relref "docs/getting-started/models" %}})_.

LocalAI's All-in-One (AIO) images are pre-configured with a set of models and backends to fully leverage almost all the features of LocalAI. If pre-configured models are not required, you can use the standard [images]({{% relref "docs/getting-started/container-images" %}}).

These images are available for both CPU and GPU environments. AIO images are designed for ease of use and require no additional configuration.

It is recommended to use AIO images if you prefer not to configure the models manually or via the web interface. For running specific models, refer to the [manual method]({{% relref "docs/getting-started/models" %}}).

The AIO images come pre-configured with the following features:
- Text to Speech (TTS)
- Speech to Text
- Function calling
- Large Language Models (LLM) for text generation
- Image generation
- Embedding server

For instructions on using AIO images, see [Using container images]({{% relref "docs/getting-started/container-images#all-in-one-images" %}}).

## What's Next?

There is much more to explore with LocalAI! You can run any model from Hugging Face, perform video generation, and also voice cloning. For a comprehensive overview, check out the [features]({{% relref "docs/features" %}}) section.

Explore additional resources and community contributions:

- [Installer Options]({{% relref "docs/advanced/installer" %}})
- [Run from Container images]({{% relref "docs/getting-started/container-images" %}})
- [Examples to try from the CLI]({{% relref "docs/getting-started/try-it-out" %}})
- [Build LocalAI and the container image]({{% relref "docs/getting-started/build" %}})
- [Run models manually]({{% relref "docs/getting-started/models" %}})
- [Examples](https://github.com/mudler/LocalAI/tree/master/examples#examples)
