const express = require('express');
const puppeteer = require('puppeteer');
const fs = require('fs');
const { exec } = require("child_process");
const path = require('path');

const app = express();

// Middleware to parse JSON bodies.
app.use(express.json());

// Main test endpoint: Generates a screenshot using Puppeteer.
app.get('/', async (req, res) => {
  try {
    const browser = await puppeteer.launch({
      headless: "new",
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage'
      ]
    });
    const page = await browser.newPage();

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>Puppeteer Test</title>
        <style>
          body { 
            font-family: Arial, sans-serif; 
            display: flex; 
            align-items: center; 
            justify-content: center; 
            height: 100vh; 
            margin: 0; 
          }
          h1 { 
            color: #0070f3; 
          }
        </style>
      </head>
      <body>
        <h1>Hello from Puppeteer + Render!</h1>
      </body>
      </html>
    `;

    await page.setContent(html, { waitUntil: 'networkidle0' });
    const screenshotPath = './output.png';
    await page.screenshot({ path: screenshotPath });
    await browser.close();

    res.send('✅ Screenshot created! Check the file output.png on the server.');
  } catch (err) {
    console.error('Error in GET /:', err);
    res.status(500).send('Something went wrong while taking a screenshot.');
  }
});

// Endpoint to download the generated slideshow video.
app.get('/download', (req, res) => {
  const file = path.join(__dirname, 'slideshow.mp4');
  res.download(file, 'slideshow.mp4', (err) => {
    if (err) {
      console.error("File download error:", err);
      res.status(404).send('File not found');
    }
  });
});

// Updated endpoint to trigger the video rendering script.
app.post('/trigger-render', (req, res) => {
  console.log("Received /trigger-render POST request");

  // Define the path for the payload file.
  const payloadFile = path.join(__dirname, 'payload.json');

  // Write the JSON payload from n8n to payload.json
  try {
    fs.writeFileSync(payloadFile, JSON.stringify(req.body, null, 2));
    console.log(`Payload written to ${payloadFile}`);
  } catch (err) {
    console.error("Error writing payload:", err);
    return res.status(500).send("Failed to write payload.");
  }

  // Immediately respond to the client so n8n doesn't time out.
  res.send({ success: true, message: "Render job queued for processing." });

  // Execute your render script asynchronously.
  const scriptPath = path.join(__dirname, 'render-video.sh');
  const command = `bash ${scriptPath} ${payloadFile}`;
  console.log(`Executing command asynchronously: ${command}`);

  exec(command, (error, stdout, stderr) => {
    if (error) {
      console.error(`Render script execution error: ${error}`);
      // Optionally log or update a job status.
      return;
    }
    console.log("Render script output:", stdout);
    console.error("Render script errors:", stderr);
    // Optionally, notify completion via another channel.
  });
});

// Use the port provided by Render or default to 3000.
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
