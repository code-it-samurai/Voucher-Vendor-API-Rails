<div style="text-align:center;">
  <h1 style="font-size:4em;font-weight:800;color:#ffffff;margin-bottom:0;letter-spacing:-0.03em;">Voucher Vendor<br>API</h1>
  <p style="font-size:0.85em;color:#666666;margin-top:0.5em;font-weight:400;letter-spacing:0.02em;">by Prat & AI</p>
  <p style="font-size:0.95em;color:#999999;margin-top:1.5em;max-width:520px;display:inline-block;line-height:1.7;">Concurreny-safe, idempotent, admin-controlled voucher distribution service with realistic async fulfillment</p>
</div>

<div style="position:relative;max-width:620px;margin:2.5em auto 0;text-align:left;">
  <pre style="background:#0a0a0a;border:1px solid #1a1a1a;border-radius:8px;padding:1.2em 1.4em;margin:0;overflow-x:auto;"><code style="font-size:0.82em;color:#e2e8f0;"><span style="color:#f87171;">git</span> clone https://github.com/code-it-samurai/Voucher-Vendor-API-Rails.git
<span style="color:#f87171;">cd</span> Voucher-Vendor-API-Rails
<span style="color:#f87171;">docker</span> compose up --build
<span style="color:#6b7280;"># API live at localhost:3000 — start making requests</span></code></pre>
  <button onclick="var self=this;var code=this.parentElement.querySelector('code');navigator.clipboard.writeText(code.textContent).then(function(){self.textContent='Copied!';setTimeout(function(){self.textContent='Copy'},2000)}).catch(function(){var t=document.createElement('textarea');t.value=code.textContent;t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();document.execCommand('copy');document.body.removeChild(t);self.textContent='Copied!';setTimeout(function(){self.textContent='Copy'},2000)})" style="position:absolute;top:8px;right:8px;background:#222;color:#aaa;border:1px solid #333;border-radius:4px;padding:4px 12px;cursor:pointer;font-size:0.8em;">Copy</button>
</div>

[Quick Walkthrough](walkthrough.md)
[Observability](observability.md)
[Postman Collection](postman.md)
[API Guide](api-reference.md)
[Github Repo](https://github.com/code-it-samurai/Voucher-Vendor-API-Rails)
