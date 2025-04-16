const express = require('express');
const puppeteer = require('puppeteer');
const fs = require('fs');
const { spawn } = require("child_process");
const path = require('path');

const app = express();
app.use(express.json());

// Main test endpoint
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
          body { font-family: Arial, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
          h1 { color: #0070f3; }
        </style>
      </head>
      <body>
        <h1>Hello from Puppeteer + Render!</h1>
      </body>
      </html>
    `;

    await page.setContent(html, { waitUntil: 'networkidle0' });
    await page.screenshot({ path: './output.png' });
    await browser.close();

    res.send('✅ Screenshot created! Check the file output.png on the server.');
  } catch (err) {
    console.error('Error in GET /:', err);
    res.status(500).send('Something went wrong while taking a screenshot.');
  }
});

// ✅ Updated download endpoint
app.get('/download', (req, res) => {
  const file = path.join(__dirname, 'final_video.mp4');
  res.download(file, 'final_video.mp4', (err) => {
    if (err) {
      console.error("File download error:", err);
      res.status(404).send('File not found');
    }
  });
});

// Optional: status check to verify if render is done
app.get('/status', (req, res) => {
  const finalPath = path.join(__dirname, 'final_video.mp4');
  const exists = fs.existsSync(finalPath);
  res.json({ done: exists });
});

// Trigger render script
app.post('/trigger-render', (req, res) => {
  console.log("Received /trigger-render POST request");

  const payloadFile = path.join(__dirname, 'payload.json');
  try {
    fs.writeFileSync(payloadFile, JSON.stringify(req.body, null, 2));
    console.log(`Payload written to ${payloadFile}`);
  } catch (err) {
    console.error("Error writing payload:", err);
    return res.status(500).send("Failed to write payload.");
  }

  res.send({ success: true, message: "Render job queued for processing." });

  const scriptPath = path.join(__dirname, 'render-video.sh');
  const child = spawn("bash", [scriptPath, payloadFile]);

  child.stdout.on("data", (data) => {
    console.log(`render-video.sh stdout: ${data}`);
  });

  child.stderr.on("data", (data) => {
    console.error(`render-video.sh stderr: ${data}`);
  });

  child.on("close", (code) => {
    console.log(`render-video.sh process exited with code ${code}`);
  });
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
