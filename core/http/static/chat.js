/*

https://github.com/david-haerer/chatapi

MIT License

Copyright (c) 2023 David Härer
Copyright (c) 2024 Ettore Di Giacinto

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

function toggleLoader(show) {
  const loader = document.getElementById('loader');
  const sendButton = document.getElementById('send-button');
  
  if (show) {
    loader.style.display = 'block';
    sendButton.style.display = 'none';
    document.getElementById("input").disabled = true;
  } else {
    document.getElementById("input").disabled = false;
    loader.style.display = 'none';
    sendButton.style.display = 'block';
  }
}

function submitSystemPrompt(event) {
  event.preventDefault();
  localStorage.setItem("system_prompt", document.getElementById("systemPrompt").value);
  document.getElementById("systemPrompt").blur();
}

var image = "";
var audio = "";
var fileContent = "";
var currentFileName = "";

async function extractTextFromPDF(pdfData) {
  try {
    const pdf = await pdfjsLib.getDocument({ data: pdfData }).promise;
    let fullText = '';
    
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const textContent = await page.getTextContent();
      const pageText = textContent.items.map(item => item.str).join(' ');
      fullText += pageText + '\n';
    }
    
    return fullText;
  } catch (error) {
    console.error('Error extracting text from PDF:', error);
    throw error;
  }
}

function readInputFile() {
  if (!this.files || !this.files[0]) return;

  const file = this.files[0];
  const FR = new FileReader();
  currentFileName = file.name;
  const fileExtension = file.name.split('.').pop().toLowerCase();
  
  FR.addEventListener("load", async function(evt) {
    if (fileExtension === 'pdf') {
      try {
        fileContent = await extractTextFromPDF(evt.target.result);
      } catch (error) {
        console.error('Error processing PDF:', error);
        fileContent = "Error processing PDF file";
      }
    } else {
      // For text and markdown files
      fileContent = evt.target.result;
    }
  });

  if (fileExtension === 'pdf') {
    FR.readAsArrayBuffer(file);
  } else {
    FR.readAsText(file);
  }
}

function submitPrompt(event) {
  event.preventDefault();

  const input = document.getElementById("input").value;
  let fullInput = input;
  
  // If there's file content, append it to the input for the LLM
  if (fileContent) {
    fullInput += "\n\nFile content:\n" + fileContent;
  }
  
  // Show file icon in chat if there's a file
  let displayContent = input;
  if (currentFileName) {
    displayContent += `\n\n<i class="fa-solid fa-file"></i> Attached file: ${currentFileName}`;
  }
  
  // Add the message to the chat UI with just the icon
  Alpine.store("chat").add("user", displayContent, image, audio);
  
  // Update the last message in the store with the full content
  const history = Alpine.store("chat").history;
  if (history.length > 0) {
    history[history.length - 1].content = fullInput;
  }
  
  document.getElementById("input").value = "";
  const systemPrompt = localStorage.getItem("system_prompt");
  Alpine.nextTick(() => { document.getElementById('messages').scrollIntoView(false); });
  promptGPT(systemPrompt, fullInput);
  
  // Reset file content and name after sending
  fileContent = "";
  currentFileName = "";
}

function readInputImage() {
  if (!this.files || !this.files[0]) return;

  const FR = new FileReader();

  FR.addEventListener("load", function(evt) {
    image = evt.target.result;
  });

  FR.readAsDataURL(this.files[0]);
}

function readInputAudio() {
  if (!this.files || !this.files[0]) return;

  const FR = new FileReader();

  FR.addEventListener("load", function(evt) {
    audio = evt.target.result;
  });

  FR.readAsDataURL(this.files[0]);
}

async function promptGPT(systemPrompt, input) {
  const model = document.getElementById("chat-model").value;
  toggleLoader(true);

  messages = Alpine.store("chat").messages();

  // if systemPrompt isn't empty, push it at the start of messages
  if (systemPrompt) {
    messages.unshift({
      role: "system",
      content: systemPrompt
    });
  }

  // loop all messages, and check if there are images or audios. If there are, we need to change the content field
  messages.forEach((message) => {
    if (message.image || message.audio) {
      // The content field now becomes an array
      message.content = [
        {
          "type": "text",
          "text": message.content
        }
      ]
      
      if (message.image) {
        message.content.push(
          {
            "type": "image_url",
            "image_url": {
              "url": message.image,
            }
          }
        );
        delete message.image;
      }

      if (message.audio) {
        message.content.push(
          {
            "type": "audio_url",
            "audio_url": {
              "url": message.audio,
            }
          }
        );
        delete message.audio;
      }
    }
  });

  // reset the form and the files
  image = "";
  audio = "";
  document.getElementById("input_image").value = null;
  document.getElementById("input_audio").value = null;
  document.getElementById("fileName").innerHTML = "";

  // Source: https://stackoverflow.com/a/75751803/11386095
  const response = await fetch("v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: model,
      messages: messages,
      stream: true,
    }),
  });

  if (!response.ok) {
    Alpine.store("chat").add(
      "assistant",
      `<span class='error'>Error: POST /v1/chat/completions ${response.status}</span>`,
    );
    return;
  }

  const reader = response.body
    ?.pipeThrough(new TextDecoderStream())
    .getReader();

  if (!reader) {
    Alpine.store("chat").add(
      "assistant",
      `<span class='error'>Error: Failed to decode API response</span>`,
    );
    return;
  }

  // Function to add content to the chat and handle DOM updates efficiently
  const addToChat = (token) => {
    const chatStore = Alpine.store("chat");
    chatStore.add("assistant", token);
    // Efficiently scroll into view without triggering multiple reflows
    // const messages = document.getElementById('messages');
    // messages.scrollTop = messages.scrollHeight;
  };

  let buffer = "";
  let contentBuffer = [];

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;

      buffer += value;

      let lines = buffer.split("\n");
      buffer = lines.pop(); // Retain any incomplete line in the buffer

      lines.forEach((line) => {
        if (line.length === 0 || line.startsWith(":")) return;
        if (line === "data: [DONE]") {
          return;
        }

        if (line.startsWith("data: ")) {
          try {
            const jsonData = JSON.parse(line.substring(6));
            const token = jsonData.choices[0].delta.content;

            if (token) {
              contentBuffer.push(token);
            }
          } catch (error) {
            console.error("Failed to parse line:", line, error);
          }
        }
      });

      // Efficiently update the chat in batch
      if (contentBuffer.length > 0) {
        addToChat(contentBuffer.join(""));
        contentBuffer = [];
      }
    }

    // Final content flush if any data remains
    if (contentBuffer.length > 0) {
      addToChat(contentBuffer.join(""));
    }

    // Highlight all code blocks once at the end
    hljs.highlightAll();
  } catch (error) {
    console.error("An error occurred while reading the stream:", error);
    Alpine.store("chat").add(
      "assistant",
      `<span class='error'>Error: Failed to process stream</span>`,
    );
  } finally {
    // Perform any cleanup if necessary
    reader.releaseLock();
  }

  // Remove class "loader" from the element with "loader" id
  toggleLoader(false);

  // scroll to the bottom of the chat
  document.getElementById('messages').scrollIntoView(false)
  // set focus to the input
  document.getElementById("input").focus();
}

document.getElementById("system_prompt").addEventListener("submit", submitSystemPrompt);
document.getElementById("prompt").addEventListener("submit", submitPrompt);
document.getElementById("input").focus();
document.getElementById("input_image").addEventListener("change", readInputImage);
document.getElementById("input_audio").addEventListener("change", readInputAudio);
document.getElementById("input_file").addEventListener("change", readInputFile);

storesystemPrompt = localStorage.getItem("system_prompt");
if (storesystemPrompt) {
  document.getElementById("systemPrompt").value = storesystemPrompt;
} else {
  document.getElementById("systemPrompt").value = null;
}

marked.setOptions({
  highlight: function (code) {
    return hljs.highlightAuto(code).value;
  },
});
