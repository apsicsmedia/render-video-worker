const express = require('express');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const app = express();
app.use(express.json());

// Trigger render
app.post('/trigger-render', (req, res) => {
  const payloadFile = path.join(__dirname, 'payload.json');
  console.log('✅ Received render request:', req.body);
  fs.writeFileSync(payloadFile, JSON.stringify(req.body, null, 2));
  console.log('✅ Payload written to:', payloadFile);

  // Acknowledge immediately so n8n doesn’t time out
  res.json({ success: true, message: 'Render job started.' });

  const scriptPath = path.join(__dirname, 'render-video.sh');
  console.log('🎞️ Launching render script:', scriptPath);

  const child = spawn('bash', [scriptPath, payloadFile]);

  child.stdout.on('data', (data) => {
    console.log(`stdout: ${data}`);
  });

  child.stderr.on('data', (data) => {
    console.error(`stderr: ${data}`);
  });

  child.on('exit', (code) => {
    if (code === 0) {
      console.log('✅ Render process completed successfully.');
    } else {
      console.error(`❌ Render process failed with exit code ${code}`);
    }
  });
});

// Download endpoint
app.get('/download', (req, res) => {
  const filePath = path.join(__dirname, 'final_video.mp4');
  console.log('📥 Download requested for:', filePath);
  if (fs.existsSync(filePath)) {
    res.download(filePath);
  } else {
    res.status(404).send('File not found');
  }
});

// Status endpoint
app.get('/status', (req, res) => {
  const exists = fs.existsSync(path.join(__dirname, 'final_video.mp4'));
  console.log('🛠️ Video status:', exists);
  res.json({ done: exists });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));
