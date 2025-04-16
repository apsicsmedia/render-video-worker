const express = require('express');
const fs = require('fs');
const path = require('path');
const { spawn } = require("child_process");

const app = express();
app.use(express.json());

// Trigger render
app.post('/trigger-render', (req, res) => {
  const payloadFile = path.join(__dirname, 'payload.json');
  fs.writeFileSync(payloadFile, JSON.stringify(req.body, null, 2));
  res.send({ success: true, message: "Render job started." });

  const scriptPath = path.join(__dirname, 'render-video.sh');
  const child = spawn("bash", [scriptPath, payloadFile]);

  child.stdout.on("data", (data) => {
    if (data.toString().includes("SUCCESS")) {
      console.log("✅ Render complete");
    }
  });

  child.stderr.on("data", (data) => {
    console.error(`❌ Render error: ${data}`);
  });
});

// Download endpoint
app.get('/download', (req, res) => {
  const filePath = path.join(__dirname, 'final_video.mp4');
  if (fs.existsSync(filePath)) {
    res.download(filePath, 'final_video.mp4');
  } else {
    res.status(404).send('File not found');
  }
});

// Optional: Check status
app.get('/status', (req, res) => {
  const exists = fs.existsSync(path.join(__dirname, 'final_video.mp4'));
  res.json({ done: exists });
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server ready on http://localhost:${PORT}`);
});
