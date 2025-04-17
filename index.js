const express = require('express');
const fs = require('fs');
const path = require('path');
const { spawn } = require("child_process");

const app = express();
app.use(express.json());

// Trigger render
app.post('/trigger-render', (req, res) => {
  const payloadFile = path.join(__dirname, 'payload.json');
  
  // Log incoming request
  console.log("✅ Received render request:", req.body);
  
  // Write the payload to a file
  fs.writeFileSync(payloadFile, JSON.stringify(req.body, null, 2));
  console.log("✅ Payload written to:", payloadFile);

  // Respond to n8n that the render job has started
  res.send({ success: true, message: "Render job started." });

  // Path to the render-video.sh script
  const scriptPath = path.join(__dirname, 'render-video.sh');
  console.log("🎞️ Starting render job with script:", scriptPath);

  // Spawn the bash process to run the render-video.sh script
  const child = spawn("bash", [scriptPath, payloadFile]);

  // Capture standard output (stdout) from the render process
  child.stdout.on("data", (data) => {
    console.log(`stdout: ${data}`);
    if (data.toString().includes("SUCCESS")) {
      console.log("✅ Render complete");
    }
  });

  // Capture standard error (stderr) from the render process
  child.stderr.on("data", (data) => {
    console.error(`stderr: ${data}`);
  });

  // Capture the exit code of the child process
  child.on('exit', (code) => {
    if (code === 0) {
      console.log("✅ Render process completed successfully.");
    } else {
      console.error(`❌ Render process failed with exit code ${code}`);
    }
  });
});

// Download endpoint
app.get('/download', (req, res) => {
  const filePath = path.join(__dirname, 'final_video.mp4');
  
  // Log the download attempt
  console.log("📥 Download requested for final video:", filePath);
  
  if (fs.existsSync(filePath)) {
    res.download(filePath, 'final_video.mp4');
  } else {
    res.status(404).send('File not found');
  }
});

// Optional: Check status of video generation
app.get('/status', (req, res) => {
  const exists = fs.existsSync(path.join(__dirname, 'final_video.mp4'));
  console.log("🛠️ Video file status: ", exists ? "Generated" : "Not yet generated");
  res.json({ done: exists });
});

// Start the Express server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server ready on http://localhost:${PORT}`);
});
