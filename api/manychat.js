// Vercel serverless function — proxies ManyChat API calls
// to avoid CORS issues from the browser.
// Usage: POST /api/manychat { path: "/fb/page/getInfo", apiKey: "..." }

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { path, apiKey } = req.body || {};

  if (!path || !apiKey) {
    return res.status(400).json({ error: 'Missing path or apiKey' });
  }

  if (!path.startsWith('/fb/')) {
    return res.status(400).json({ error: 'Invalid API path' });
  }

  try {
    const resp = await fetch('https://api.manychat.com' + path, {
      headers: {
        'Authorization': 'Bearer ' + apiKey,
        'Accept': 'application/json'
      }
    });

    const data = await resp.json();
    return res.status(resp.status).json(data);
  } catch (e) {
    return res.status(502).json({ error: 'ManyChat API request failed', message: e.message });
  }
};
