<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpsDesk</title>
  <link rel="stylesheet" href="/assets/css/app.css">
</head>
<body>
  <main class="shell">
    <section class="workspace">
      <aside class="sidebar">
        <div class="brand">
          <span class="brand-mark">OD</span>
          <div>
            <strong>OpsDesk</strong>
            <span>Service command</span>
          </div>
        </div>

        <nav class="nav">
          <button class="nav-item active" data-status="all">All incidents</button>
          <button class="nav-item" data-status="open">Open</button>
          <button class="nav-item" data-status="investigating">Investigating</button>
          <button class="nav-item" data-status="resolved">Resolved</button>
        </nav>

        <div class="connection">
          <span id="health-dot" class="dot"></span>
          <span id="health-text">Checking database</span>
        </div>
      </aside>

      <section class="content">
        <header class="topbar">
          <div>
            <p class="eyebrow">Layer 1 web tier</p>
            <h1>Incident operations</h1>
          </div>
          <button id="refresh-btn" class="icon-button" title="Refresh incidents" aria-label="Refresh incidents">R</button>
        </header>

        <section class="metrics" aria-label="Incident summary">
          <article class="metric">
            <span>Total</span>
            <strong id="metric-total">0</strong>
          </article>
          <article class="metric danger">
            <span>Critical open</span>
            <strong id="metric-critical">0</strong>
          </article>
          <article class="metric">
            <span>Open</span>
            <strong id="metric-open">0</strong>
          </article>
          <article class="metric">
            <span>Investigating</span>
            <strong id="metric-investigating">0</strong>
          </article>
        </section>

        <section class="main-grid">
          <form id="incident-form" class="panel form-panel">
            <h2>New incident</h2>
            <label>
              Title
              <input name="title" maxlength="180" required placeholder="API latency above threshold">
            </label>
            <label>
              Service
              <input name="service_name" maxlength="120" required placeholder="checkout-api">
            </label>
            <div class="field-row">
              <label>
                Severity
                <select name="severity">
                  <option value="medium">Medium</option>
                  <option value="low">Low</option>
                  <option value="high">High</option>
                  <option value="critical">Critical</option>
                </select>
              </label>
              <label>
                Owner
                <input name="owner" maxlength="120" placeholder="Platform Team">
              </label>
            </div>
            <label>
              Notes
              <textarea name="description" rows="4" maxlength="1000" placeholder="Short context for the response team"></textarea>
            </label>
            <button class="primary-button" type="submit">Create incident</button>
          </form>

          <section class="panel incident-panel">
            <div class="panel-heading">
              <h2>Response queue</h2>
              <span id="active-filter">all</span>
            </div>
            <div id="incident-list" class="incident-list"></div>
          </section>
        </section>
      </section>
    </section>
  </main>

  <template id="incident-template">
    <article class="incident-card">
      <div class="incident-main">
        <span class="severity"></span>
        <div>
          <h3></h3>
          <p></p>
        </div>
      </div>
      <div class="incident-actions">
        <select class="status-select">
          <option value="open">Open</option>
          <option value="investigating">Investigating</option>
          <option value="resolved">Resolved</option>
        </select>
      </div>
    </article>
  </template>

  <script src="/assets/js/app.js"></script>
</body>
</html>
