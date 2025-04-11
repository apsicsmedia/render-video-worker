const express = require('express');
const puppeteer = require('puppeteer');
const fs = require('fs');
const { exec } = require("child_process");

const app = express();

// Main test endpoint: Generates a screenshot using Puppeteer.
app.get('/', async (req, res) => {
  try {
    // Launch Puppeteer with enhanced options:
    // - headless: "new" opts in to the new headless mode for improved stability.
    // - --no-sandbox and --disable-setuid-sandbox: required in many cloud environments.
    // - --disable-dev-shm-usage: reduces shared memory usage.
    const browser = await puppeteer.launch({
      headless: "new",
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage'
      ]
    });
    const page = await browser.newPage();

    // Define a simple HTML page for testing.
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

    // Set the page content and wait until all network requests have finished.
    await page.setContent(html, { waitUntil: 'networkidle0' });
    
    // Take a screenshot and save it as output.png.
    const screenshotPath = './output.png';
    await page.screenshot({ path: screenshotPath });

    await browser.close();

    // Send a success response.
    res.send('✅ Screenshot created! Check the file output.png on the server.');
  } catch (err) {
    console.error('Error in GET /:', err);
    res.status(500).send('Something went wrong while taking a screenshot.');
  }
});

// Endpoint to download the generated slideshow video.
app.get('/download', (req, res) => {
  const file = __dirname + '/slideshow.mp4';
  res.download(file, 'slideshow.mp4', (err) => {
    if (err) {
      console.error("File download error:", err);
      res.status(404).send('File not found');
    }
  });
});

// Endpoint to trigger the video rendering script.
app.post('/trigger-render', (req, res) => {
  console.log("Received /trigger-render POST request");
  // Execute the render-video.sh script.
  exec("bash render-video.sh", (error, stdout, stderr) => {
    if (error) {
      console.error(`Execution error: ${error}`);
      return res.status(500).send(`Error executing render script: ${error}`);
    }
    console.log("Render script output:", stdout);
    res.send(`Render script executed successfully. Output: ${stdout}`);
  });
});

// Use the port provided by Render or default to 3000.
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
