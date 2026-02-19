#!/usr/bin/env node
/**
 * MindVault MCP Server - Google Drive Integration
 * 
 * This MCP server provides tools to:
 * - List files from Google Drive
 * - Download and process PDFs, Docs, and other documents
 * - Extract text content for RAG indexing
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { google } from "googleapis";
import { OAuth2Client } from "google-auth-library";
import * as fs from "fs";
import * as path from "path";
import pdfParse from "pdf-parse";
import mammoth from "mammoth";

// Configuration
const CONFIG_DIR = path.join(process.env.HOME || "~", ".mindvault");
const TOKEN_PATH = path.join(CONFIG_DIR, "drive_token.json");
const CREDENTIALS_PATH = path.join(CONFIG_DIR, "drive_credentials.json");

// Ensure config directory exists
if (!fs.existsSync(CONFIG_DIR)) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true });
}

// OAuth2 scopes for Google Drive
const SCOPES = [
  "https://www.googleapis.com/auth/drive.readonly",
  "https://www.googleapis.com/auth/drive.metadata.readonly",
];

// Initialize OAuth2 client
let oauth2Client: OAuth2Client | null = null;

async function getOAuth2Client(): Promise<OAuth2Client | null> {
  if (oauth2Client) return oauth2Client;

  try {
    if (!fs.existsSync(CREDENTIALS_PATH)) {
      console.error(`Credentials file not found at ${CREDENTIALS_PATH}`);
      return null;
    }

    const credentials = JSON.parse(fs.readFileSync(CREDENTIALS_PATH, "utf-8"));
    const { client_id, client_secret, redirect_uris } = credentials.installed || credentials.web;

    oauth2Client = new OAuth2Client(client_id, client_secret, redirect_uris[0]);

    // Load saved token if exists
    if (fs.existsSync(TOKEN_PATH)) {
      const token = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf-8"));
      oauth2Client.setCredentials(token);
    }

    return oauth2Client;
  } catch (error) {
    console.error("Error initializing OAuth2 client:", error);
    return null;
  }
}

// Document processing functions
async function extractPdfText(buffer: Buffer): Promise<string> {
  try {
    const data = await pdfParse(buffer);
    return data.text;
  } catch (error) {
    console.error("Error extracting PDF text:", error);
    return "";
  }
}

async function extractDocxText(buffer: Buffer): Promise<string> {
  try {
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  } catch (error) {
    console.error("Error extracting DOCX text:", error);
    return "";
  }
}

async function extractGoogleDocText(drive: any, fileId: string): Promise<string> {
  try {
    const response = await drive.files.export({
      fileId,
      mimeType: "text/plain",
    });
    return response.data as string;
  } catch (error) {
    console.error("Error extracting Google Doc text:", error);
    return "";
  }
}

// Create MCP Server
const server = new Server(
  {
    name: "mindvault-drive",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "drive_auth_url",
        description: "Get the Google Drive OAuth2 authorization URL. User needs to visit this URL to authorize access.",
        inputSchema: {
          type: "object",
          properties: {},
          required: [],
        },
      },
      {
        name: "drive_auth_callback",
        description: "Complete OAuth2 authorization with the code from the callback URL",
        inputSchema: {
          type: "object",
          properties: {
            code: {
              type: "string",
              description: "The authorization code from the OAuth2 callback",
            },
          },
          required: ["code"],
        },
      },
      {
        name: "drive_list_files",
        description: "List files from Google Drive. Can filter by folder, file type, and search query.",
        inputSchema: {
          type: "object",
          properties: {
            folderId: {
              type: "string",
              description: "Optional folder ID to list files from. Use 'root' for root folder.",
            },
            query: {
              type: "string",
              description: "Optional search query to filter files",
            },
            mimeType: {
              type: "string",
              description: "Optional MIME type filter (e.g., 'application/pdf')",
            },
            pageSize: {
              type: "number",
              description: "Number of files to return (max 100)",
            },
          },
          required: [],
        },
      },
      {
        name: "drive_get_file",
        description: "Get metadata and content of a specific file from Google Drive",
        inputSchema: {
          type: "object",
          properties: {
            fileId: {
              type: "string",
              description: "The ID of the file to retrieve",
            },
          },
          required: ["fileId"],
        },
      },
      {
        name: "drive_download_and_process",
        description: "Download a file from Google Drive and extract its text content for indexing",
        inputSchema: {
          type: "object",
          properties: {
            fileId: {
              type: "string",
              description: "The ID of the file to download and process",
            },
          },
          required: ["fileId"],
        },
      },
      {
        name: "drive_sync_folder",
        description: "Sync all documents from a folder to the MindVault RAG system",
        inputSchema: {
          type: "object",
          properties: {
            folderId: {
              type: "string",
              description: "The folder ID to sync. Use 'root' for root folder.",
            },
            recursive: {
              type: "boolean",
              description: "Whether to sync subfolders recursively",
            },
          },
          required: ["folderId"],
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "drive_auth_url": {
      const client = await getOAuth2Client();
      if (!client) {
        return {
          content: [
            {
              type: "text",
              text: `Error: OAuth2 client not initialized. Please ensure credentials file exists at ${CREDENTIALS_PATH}`,
            },
          ],
        };
      }

      const authUrl = client.generateAuthUrl({
        access_type: "offline",
        scope: SCOPES,
        prompt: "consent",
      });

      return {
        content: [
          {
            type: "text",
            text: `Please visit this URL to authorize Google Drive access:\n\n${authUrl}\n\nAfter authorization, you'll receive a code. Use the 'drive_auth_callback' tool with that code.`,
          },
        ],
      };
    }

    case "drive_auth_callback": {
      const { code } = args as { code: string };
      const client = await getOAuth2Client();

      if (!client) {
        return {
          content: [
            { type: "text", text: "Error: OAuth2 client not initialized" },
          ],
        };
      }

      try {
        const { tokens } = await client.getToken(code);
        client.setCredentials(tokens);

        // Save token for future use
        fs.writeFileSync(TOKEN_PATH, JSON.stringify(tokens));

        return {
          content: [
            {
              type: "text",
              text: "Successfully authenticated with Google Drive! You can now use other drive tools.",
            },
          ],
        };
      } catch (error) {
        return {
          content: [
            { type: "text", text: `Error exchanging code for token: ${error}` },
          ],
        };
      }
    }

    case "drive_list_files": {
      const { folderId, query, mimeType, pageSize } = args as {
        folderId?: string;
        query?: string;
        mimeType?: string;
        pageSize?: number;
      };

      const client = await getOAuth2Client();
      if (!client || !client.credentials.access_token) {
        return {
          content: [
            {
              type: "text",
              text: "Error: Not authenticated. Please use 'drive_auth_url' first.",
            },
          ],
        };
      }

      const drive = google.drive({ version: "v3", auth: client });

      // Build query
      let q = "trashed = false";
      if (folderId) {
        q += ` and '${folderId}' in parents`;
      }
      if (mimeType) {
        q += ` and mimeType = '${mimeType}'`;
      }
      if (query) {
        q += ` and (name contains '${query}' or fullText contains '${query}')`;
      }

      try {
        const response = await drive.files.list({
          q,
          pageSize: pageSize || 20,
          fields: "files(id, name, mimeType, size, modifiedTime, parents, webViewLink)",
        });

        const files = response.data.files || [];

        if (files.length === 0) {
          return {
            content: [{ type: "text", text: "No files found matching the criteria." }],
          };
        }

        const fileList = files.map((f) => ({
          id: f.id,
          name: f.name,
          type: f.mimeType,
          size: f.size ? `${Math.round(parseInt(f.size) / 1024)} KB` : "N/A",
          modified: f.modifiedTime,
          link: f.webViewLink,
        }));

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(fileList, null, 2),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Error listing files: ${error}` }],
        };
      }
    }

    case "drive_get_file": {
      const { fileId } = args as { fileId: string };

      const client = await getOAuth2Client();
      if (!client || !client.credentials.access_token) {
        return {
          content: [
            { type: "text", text: "Error: Not authenticated. Please use 'drive_auth_url' first." },
          ],
        };
      }

      const drive = google.drive({ version: "v3", auth: client });

      try {
        const response = await drive.files.get({
          fileId,
          fields: "id, name, mimeType, size, modifiedTime, description, webViewLink, parents",
        });

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Error getting file: ${error}` }],
        };
      }
    }

    case "drive_download_and_process": {
      const { fileId } = args as { fileId: string };

      const client = await getOAuth2Client();
      if (!client || !client.credentials.access_token) {
        return {
          content: [
            { type: "text", text: "Error: Not authenticated. Please use 'drive_auth_url' first." },
          ],
        };
      }

      const drive = google.drive({ version: "v3", auth: client });

      try {
        // Get file metadata
        const metadata = await drive.files.get({
          fileId,
          fields: "id, name, mimeType, size, modifiedTime",
        });

        const mimeType = metadata.data.mimeType || "";
        const fileName = metadata.data.name || "unknown";
        let extractedText = "";

        // Process based on file type
        if (mimeType === "application/pdf") {
          // Download PDF
          const response = await drive.files.get(
            { fileId, alt: "media" },
            { responseType: "arraybuffer" }
          );
          const buffer = Buffer.from(response.data as ArrayBuffer);
          extractedText = await extractPdfText(buffer);
        } else if (mimeType === "application/vnd.google-apps.document") {
          // Export Google Doc as plain text
          extractedText = await extractGoogleDocText(drive, fileId);
        } else if (
          mimeType === "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ) {
          // Download and process DOCX
          const response = await drive.files.get(
            { fileId, alt: "media" },
            { responseType: "arraybuffer" }
          );
          const buffer = Buffer.from(response.data as ArrayBuffer);
          extractedText = await extractDocxText(buffer);
        } else if (mimeType === "text/plain" || mimeType === "text/markdown") {
          // Download text file
          const response = await drive.files.get(
            { fileId, alt: "media" },
            { responseType: "text" }
          );
          extractedText = response.data as string;
        } else if (mimeType === "application/vnd.google-apps.spreadsheet") {
          // Export Google Sheet as CSV
          const response = await drive.files.export({
            fileId,
            mimeType: "text/csv",
          });
          extractedText = response.data as string;
        } else {
          return {
            content: [
              {
                type: "text",
                text: `Unsupported file type: ${mimeType}. Supported types: PDF, Google Docs, DOCX, TXT, MD, Google Sheets.`,
              },
            ],
          };
        }

        // Clean up the text
        extractedText = extractedText
          .replace(/\s+/g, " ")
          .replace(/\n{3,}/g, "\n\n")
          .trim();

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                fileId,
                fileName,
                mimeType,
                modifiedTime: metadata.data.modifiedTime,
                textLength: extractedText.length,
                extractedText: extractedText.substring(0, 5000), // First 5000 chars
                truncated: extractedText.length > 5000,
              }, null, 2),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Error processing file: ${error}` }],
        };
      }
    }

    case "drive_sync_folder": {
      const { folderId, recursive } = args as { folderId: string; recursive?: boolean };

      const client = await getOAuth2Client();
      if (!client || !client.credentials.access_token) {
        return {
          content: [
            { type: "text", text: "Error: Not authenticated. Please use 'drive_auth_url' first." },
          ],
        };
      }

      const drive = google.drive({ version: "v3", auth: client });
      const processedFiles: Array<{ name: string; id: string; status: string }> = [];

      async function processFolder(fId: string) {
        const supportedMimeTypes = [
          "application/pdf",
          "application/vnd.google-apps.document",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "text/plain",
          "text/markdown",
        ];

        const q = `'${fId}' in parents and trashed = false`;

        const response = await drive.files.list({
          q,
          pageSize: 100,
          fields: "files(id, name, mimeType)",
        });

        const files = response.data.files || [];

        for (const file of files) {
          if (file.mimeType === "application/vnd.google-apps.folder") {
            if (recursive) {
              await processFolder(file.id!);
            }
          } else if (supportedMimeTypes.includes(file.mimeType || "")) {
            processedFiles.push({
              name: file.name || "unknown",
              id: file.id || "",
              status: "queued for processing",
            });
          }
        }
      }

      try {
        await processFolder(folderId);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                message: `Found ${processedFiles.length} documents to sync`,
                files: processedFiles,
                nextStep: "Use 'drive_download_and_process' for each file, then send to MindVault backend",
              }, null, 2),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Error syncing folder: ${error}` }],
        };
      }
    }

    default:
      return {
        content: [{ type: "text", text: `Unknown tool: ${name}` }],
      };
  }
});

// List resources (Drive files as resources)
server.setRequestHandler(ListResourcesRequestSchema, async () => {
  const client = await getOAuth2Client();
  if (!client || !client.credentials.access_token) {
    return { resources: [] };
  }

  const drive = google.drive({ version: "v3", auth: client });

  try {
    const response = await drive.files.list({
      q: "trashed = false and (mimeType = 'application/pdf' or mimeType = 'application/vnd.google-apps.document')",
      pageSize: 50,
      fields: "files(id, name, mimeType)",
    });

    const files = response.data.files || [];

    return {
      resources: files.map((f) => ({
        uri: `drive://${f.id}`,
        name: f.name || "Unnamed",
        description: `Google Drive file: ${f.mimeType}`,
        mimeType: f.mimeType || "application/octet-stream",
      })),
    };
  } catch (error) {
    console.error("Error listing resources:", error);
    return { resources: [] };
  }
});

// Read resource content
server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;
  const fileId = uri.replace("drive://", "");

  const client = await getOAuth2Client();
  if (!client || !client.credentials.access_token) {
    return {
      contents: [
        {
          uri,
          mimeType: "text/plain",
          text: "Error: Not authenticated with Google Drive",
        },
      ],
    };
  }

  const drive = google.drive({ version: "v3", auth: client });

  try {
    const metadata = await drive.files.get({
      fileId,
      fields: "id, name, mimeType",
    });

    const mimeType = metadata.data.mimeType || "";
    let text = "";

    if (mimeType === "application/pdf") {
      const response = await drive.files.get(
        { fileId, alt: "media" },
        { responseType: "arraybuffer" }
      );
      const buffer = Buffer.from(response.data as ArrayBuffer);
      text = await extractPdfText(buffer);
    } else if (mimeType === "application/vnd.google-apps.document") {
      text = await extractGoogleDocText(drive, fileId);
    }

    return {
      contents: [
        {
          uri,
          mimeType: "text/plain",
          text,
        },
      ],
    };
  } catch (error) {
    return {
      contents: [
        {
          uri,
          mimeType: "text/plain",
          text: `Error reading file: ${error}`,
        },
      ],
    };
  }
});

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("MindVault Drive MCP Server running on stdio");
}

main().catch(console.error);
