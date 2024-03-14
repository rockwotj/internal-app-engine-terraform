import express from 'express';
const app = express();

app.use((_req, res) => {
  res.status(200).send('Hello, world 🤪');
});
// Start the server
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`App listening on port ${PORT}`);
  console.log('Press Ctrl+C to quit.');
});
