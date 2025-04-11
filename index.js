const express = require('express');
const puppeteer = require('puppeteer');
const fs = require('fs');

const app = express();

app.get('/', async (req, res) => {
  try {
    // Launch Puppeteer with flags needed in cloud environments
    const browser = await puppeteer.launch({
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const page = await browser.newPage();

    // Define a simple HTML page
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
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

    // Set the page content and wait until it's fully loaded
    await page.setContent(html, { waitUntil: 'networkidle0' });
    
    // Take a screenshot and save it as output.png
    const screenshotPath = './output.png';
    await page.screenshot({ path: screenshotPath });

    await browser.close();

    // Send a success response
    res.send('✅ Screenshot created! Check the file output.png on the server.');
  } catch (err) {
    console.error(err);
    res.status(500).send('Something went wrong while taking a screenshot.');
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});

// New endpoint to download the slideshow video
app.get('/download', (req, res) => {
  const file = __dirname + '/slideshow.mp4';
  res.download(file, 'slideshow.mp4', (err) => {
    if (err) {
      console.error("File download error:", err);
      res.status(404).send('File not found');
    }
  });
});
const { exec } = require("child_process");

// New endpoint to trigger the video rendering script
app.post('/trigger-render', (req, res) => {
  // Run the render-video.sh script
  exec("bash render-video.sh", (error, stdout, stderr) => {
    if (error) {
      console.error(`Execution error: ${error}`);
      return res.status(500).send(`Error executing render script: ${error}`);
    }
    // Send back the output
    res.send(`Render script executed successfully. Output: ${stdout}`);
  });
});


