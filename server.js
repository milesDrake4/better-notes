const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

loadEnvFile();

const PORT = Number(process.env.PORT) || 8080;
const HOST = process.env.HOST || "0.0.0.0";
const MODEL = process.env.OPENAI_MODEL || "gpt-5-mini";
const PUBLIC_DIR = __dirname;

const mimeTypes = {
  ".css": "text/css",
  ".html": "text/html",
  ".ico": "image/x-icon",
  ".js": "text/javascript",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://${request.headers.host}`);

    if (request.method === "POST" && url.pathname === "/api/ai-transcribe") {
      await handleAiTranscribe(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/ai-feedback") {
      await handleAiFeedback(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/ai-followup") {
      await handleAiFollowup(request, response);
      return;
    }

    if (request.method !== "GET") {
      sendJson(response, 405, { error: "Method not allowed" });
      return;
    }

    serveStaticFile(url.pathname, response);
  } catch (error) {
    console.error(error);
    sendJson(response, 500, { error: "Something went wrong." });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`BetterNotes running at http://${HOST}:${PORT}`);
  console.log(`On this Mac, open http://localhost:${PORT}`);
});

function loadEnvFile() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const equalsIndex = trimmed.indexOf("=");
    if (equalsIndex === -1) continue;

    const key = trimmed.slice(0, equalsIndex).trim();
    const value = trimmed.slice(equalsIndex + 1).trim().replace(/^["']|["']$/g, "");
    if (!process.env[key]) process.env[key] = value;
  }
}

function serveStaticFile(pathname, response) {
  const requestedPath = pathname === "/" ? "/index.html" : pathname;
  const filePath = path.normalize(path.join(PUBLIC_DIR, requestedPath));
  const relativePath = path.relative(PUBLIC_DIR, filePath);

  if (
    relativePath.startsWith("..") ||
    path.isAbsolute(relativePath) ||
    relativePath.split(path.sep).some((part) => part.startsWith(".")) ||
    path.basename(filePath) === "server.js"
  ) {
    sendJson(response, 403, { error: "Forbidden" });
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      sendJson(response, 404, { error: "Not found" });
      return;
    }

    const extension = path.extname(filePath);
    response.writeHead(200, { "Content-Type": mimeTypes[extension] || "application/octet-stream" });
    response.end(content);
  });
}

async function handleAiTranscribe(request, response) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    sendJson(response, 501, {
      error: "OPENAI_API_KEY is not set. Add it to a .env file to enable real AI Lens feedback.",
    });
    return;
  }

  const body = await readJsonBody(request);
  const { image, scope } = body;

  if (!image || !image.startsWith("data:image/")) {
    sendJson(response, 400, { error: "A PNG or JPEG data URL is required." });
    return;
  }

  const responseFromOpenAi = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      text: {
        format: transcriptionSchema(),
      },
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "You are BetterNotes, an AI tutor inside a student note-taking app.",
                "Only transcribe the handwritten schoolwork in the image.",
                "If any part is unclear, say so directly in the transcription.",
                "Do not solve, grade, correct, or give feedback yet.",
                "Use LaTeX for math expressions, wrapped in inline delimiters like \\(x^2\\) or display delimiters like \\[x^2 + 1\\]. Do not double-escape the backslashes.",
                `Scan scope: ${scope || "selection"}.`,
              ].join("\n"),
            },
            {
              type: "input_image",
              image_url: image,
              detail: "high",
            },
          ],
        },
      ],
    }),
  });

  const data = await responseFromOpenAi.json();

  if (!responseFromOpenAi.ok) {
    console.error(data);
    sendJson(response, responseFromOpenAi.status, {
      error: data.error?.message || "OpenAI could not generate feedback.",
    });
    return;
  }

  const rawText = extractOutputText(data);
  const transcription = parseTranscription(rawText);
  sendJson(response, 200, transcription);
}

async function handleAiFeedback(request, response) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    sendJson(response, 501, {
      error: "OPENAI_API_KEY is not set. Add it to a .env file to enable real AI Lens feedback.",
    });
    return;
  }

  const body = await readJsonBody(request);
  const {
    transcription,
    mode,
    prompt,
    noteType,
    noteContextText,
    noteContextImages = [],
    referenceText,
    referenceImages = [],
  } = body;

  if (!transcription || !transcription.trim()) {
    sendJson(response, 400, { error: "Approved reading is required." });
    return;
  }

  const modeInstructions = getModeInstructions();
  const content = [
    {
      type: "input_text",
      text: [
        "You are BetterNotes, an AI tutor inside a student note-taking app.",
        "The student approved this reading of their work. Use it as the source of truth.",
        "Use LaTeX for math expressions, wrapped in inline delimiters like \\(x^2\\) or display delimiters like \\[x^2 + 1\\]. Do not double-escape the backslashes.",
        modeInstructions[mode] || modeInstructions.check,
        mode === "grade" && (referenceText || referenceImages.length > 0)
          ? "When grading, compare the student's work against the attached rubric, answer key, or solutions reference. If the reference conflicts with the student's work, explain the mismatch."
          : "",
        noteType && noteType !== "blank"
          ? "Use the attached assignment context to understand the original question or instructions before responding."
          : "",
        `Approved student work: ${transcription.trim()}`,
        noteContextText ? `Assignment context:\n${noteContextText}` : "",
        referenceText ? `Reference text:\n${referenceText}` : "",
        `Student request: ${prompt || "Check my work."}`,
      ]
        .filter(Boolean)
        .join("\n"),
    },
  ];

  for (const imageUrl of noteContextImages.slice(0, 4)) {
    if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
      content.push({
        type: "input_image",
        image_url: imageUrl,
        detail: "high",
      });
    }
  }

  if (mode === "grade") {
    for (const imageUrl of referenceImages.slice(0, 4)) {
      if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
        content.push({
          type: "input_image",
          image_url: imageUrl,
          detail: "high",
        });
      }
    }
  }

  const responseFromOpenAi = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      text: {
        format: feedbackSchema(),
      },
      input: [
        {
          role: "user",
          content,
        },
      ],
    }),
  });

  const data = await responseFromOpenAi.json();

  if (!responseFromOpenAi.ok) {
    console.error(data);
    sendJson(response, responseFromOpenAi.status, {
      error: data.error?.message || "OpenAI could not generate feedback.",
    });
    return;
  }

  const rawText = extractOutputText(data);
  const feedback = parseFeedback(rawText);
  sendJson(response, 200, feedback);
}

async function handleAiFollowup(request, response) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    sendJson(response, 501, {
      error: "OPENAI_API_KEY is not set. Add it to a .env file to enable real AI Lens feedback.",
    });
    return;
  }

  const body = await readJsonBody(request);
  const {
    question,
    transcription,
    latestFeedback,
    chatMessages = [],
    noteType,
    noteContextText,
    noteContextImages = [],
    notePageImage,
  } = body;

  if (!question || !question.trim()) {
    sendJson(response, 400, { error: "A follow-up question is required." });
    return;
  }

  const conversation = chatMessages
    .slice(-8)
    .map((message) => `${message.role === "user" ? "Student" : "BetterNotes"}: ${message.text}`)
    .join("\n");

  const content = [
    {
      type: "input_text",
      text: [
        "You are BetterNotes, an AI tutor in a student note-taking app.",
        "Answer the student's follow-up using the approved reading, current note page, assignment context, and prior feedback as context.",
        "If the student asks whether a specific problem is correct, inspect the current note page and match it against the assignment context when available.",
        "If there is no approved reading yet, rely on the current note page image and assignment context instead of asking the student to paste their work.",
        "Be concise, practical, and student-friendly. Use LaTeX for math with inline delimiters like \\(x^2\\).",
        noteType && noteType !== "blank"
          ? "Use the attached assignment context to understand the original question or instructions."
          : "",
        `Approved reading: ${transcription || "No approved reading available."}`,
        noteContextText ? `Assignment context:\n${noteContextText}` : "",
        latestFeedback
          ? `Latest feedback:\nTitle: ${latestFeedback.title || ""}\nBody: ${latestFeedback.body || ""}\nNext step: ${latestFeedback.nextStep || ""}`
          : "",
        conversation ? `Conversation so far:\n${conversation}` : "",
        `Student follow-up: ${question.trim()}`,
      ]
        .filter(Boolean)
        .join("\n"),
    },
  ];

  if (typeof notePageImage === "string" && notePageImage.startsWith("data:image/")) {
    content.push({
      type: "input_image",
      image_url: notePageImage,
      detail: "high",
    });
  }

  for (const imageUrl of noteContextImages.slice(0, 4)) {
    if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
      content.push({
        type: "input_image",
        image_url: imageUrl,
        detail: "high",
      });
    }
  }

  const responseFromOpenAi = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      input: [
        {
          role: "user",
          content,
        },
      ],
    }),
  });

  const data = await responseFromOpenAi.json();

  if (!responseFromOpenAi.ok) {
    console.error(data);
    sendJson(response, responseFromOpenAi.status, {
      error: data.error?.message || "OpenAI could not answer the follow-up.",
    });
    return;
  }

  sendJson(response, 200, {
    reply: extractOutputText(data) || "I could not answer that follow-up clearly.",
  });
}

function getModeInstructions() {
  return {
    check: "Check the student's work. Point out the most likely mistake or confirm what looks right. Be concise and encouraging.",
    hint: "Give a hint that helps the student make the next move without giving the full answer away.",
    grade: "Estimate a practice grade and explain the main reason for that score. Be fair, brief, and student-friendly.",
  };
}

function feedbackSchema() {
  return {
    type: "json_schema",
    name: "better_notes_feedback",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        title: { type: "string" },
        body: { type: "string" },
        nextStep: { type: "string" },
      },
      required: ["title", "body", "nextStep"],
    },
    strict: true,
  };
}

function transcriptionSchema() {
  return {
    type: "json_schema",
    name: "better_notes_transcription",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        transcription: { type: "string" },
      },
      required: ["transcription"],
    },
    strict: true,
  };
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";

    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 12_000_000) {
        reject(new Error("Request body is too large."));
      }
    });

    request.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch (error) {
        reject(error);
      }
    });

    request.on("error", reject);
  });
}

function extractOutputText(data) {
  if (data.output_text) return data.output_text;

  return (data.output || [])
    .flatMap((item) => item.content || [])
    .filter((content) => content.type === "output_text")
    .map((content) => content.text)
    .join("\n");
}

function parseFeedback(rawText) {
  try {
    const trimmedText = rawText.trim();
    const jsonStart = trimmedText.indexOf("{");
    const jsonEnd = trimmedText.lastIndexOf("}");
    const jsonText = jsonStart >= 0 && jsonEnd > jsonStart ? trimmedText.slice(jsonStart, jsonEnd + 1) : trimmedText;
    const parsed = JSON.parse(jsonText);

    return {
      title: String(parsed.title || "AI feedback"),
      body: String(parsed.body || "I could not read enough detail to give specific feedback."),
      nextStep: String(parsed.nextStep || "Try scanning a clearer or smaller section."),
    };
  } catch {
    return {
      title: "AI feedback",
      body: rawText || "I could not read enough detail to give specific feedback.",
      nextStep: "Try scanning a clearer or smaller section.",
    };
  }
}

function parseTranscription(rawText) {
  try {
    const trimmedText = rawText.trim();
    const jsonStart = trimmedText.indexOf("{");
    const jsonEnd = trimmedText.lastIndexOf("}");
    const jsonText = jsonStart >= 0 && jsonEnd > jsonStart ? trimmedText.slice(jsonStart, jsonEnd + 1) : trimmedText;
    const parsed = JSON.parse(jsonText);

    return {
      transcription: String(parsed.transcription || "I could not read enough detail to transcribe this clearly."),
    };
  } catch {
    return {
      transcription: rawText || "I could not read enough detail to transcribe this clearly.",
    };
  }
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
}
