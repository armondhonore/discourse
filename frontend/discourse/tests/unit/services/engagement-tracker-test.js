import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import sinon from "sinon";
import { processBrowserAttentionChange } from "discourse/lib/user-presence";

const SESSION_ID = "S".repeat(32);

// The tracker leans on user-presence's attention signal, whose own DOM
// listeners are disabled under isTesting(); drive the signal directly.
function blur(context) {
  context.focused = false;
  processBrowserAttentionChange();
}

function focus(context) {
  context.focused = true;
  processBrowserAttentionChange();
}

function hide(context) {
  context.visibility = "hidden";
  processBrowserAttentionChange();
}

function pagehide() {
  window.dispatchEvent(new Event("pagehide"));
}

module("Unit | Service | engagement-tracker", function (hooks) {
  setupTest(hooks);

  hooks.beforeEach(function () {
    this.clock = { ms: 0 };
    this.focused = true;
    this.visibility = "visible";
    this.sent = [];

    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      get: () => this.visibility,
    });
    sinon.stub(document, "hasFocus").callsFake(() => this.focused);

    this.meta = document.createElement("meta");
    this.meta.name = "discourse-track-view-session-id";
    this.meta.content = SESSION_ID;
    document.head.appendChild(this.meta);

    this.siteSettings = this.owner.lookup("service:site-settings");
    this.tracker = this.owner.lookup("service:engagement-tracker");
    this.tracker.now = () => this.clock.ms;
    this.tracker.transport = (body) => this.sent.push(body);

    this.buildTracker = (cap = 1800) => {
      this.siteSettings.browser_pageview_max_engaged_seconds = cap;
      this.tracker.start();
    };
  });

  hooks.afterEach(function () {
    this.tracker?.stop();
    this.meta.remove();
    delete document.visibilityState;
  });

  test("accumulates only visible-and-focused time and banks it on disengage", function (assert) {
    this.buildTracker();

    this.clock.ms = 4000;
    blur(this);

    this.clock.ms = 10_000;
    focus(this);

    this.clock.ms = 13_000;
    blur(this);

    assert.strictEqual(this.sent.at(-1).engaged_seconds, 7);
  });

  test("does not count time while the tab is hidden", function (assert) {
    this.buildTracker();

    this.clock.ms = 5000;
    hide(this);

    assert.strictEqual(this.sent.at(-1).engaged_seconds, 5);

    this.clock.ms = 20_000;
    pagehide();

    assert.strictEqual(this.sent.at(-1).engaged_seconds, 5);
  });

  test("caps engaged seconds at the configured limit", function (assert) {
    this.buildTracker(5);

    this.clock.ms = 9000;
    blur(this);

    assert.strictEqual(this.sent.at(-1).engaged_seconds, 5);
  });

  test("keeps accumulating across many engage and disengage cycles", function (assert) {
    this.buildTracker();

    this.clock.ms = 2000;
    blur(this);
    this.clock.ms = 5000;
    focus(this);
    this.clock.ms = 8000;
    blur(this);
    this.clock.ms = 11_000;
    focus(this);
    this.clock.ms = 14_000;
    pagehide();

    assert.strictEqual(this.sent.at(-1).engaged_seconds, 8);
  });

  test("posts the session id from the meta tag and the engaged seconds on disengage", function (assert) {
    this.buildTracker();

    this.clock.ms = 3000;
    blur(this);

    assert.deepEqual(this.sent.at(-1), {
      session_id: SESSION_ID,
      engaged_seconds: 3,
    });
  });

  test("throttles sends to at most one every three seconds", function (assert) {
    this.buildTracker();

    this.clock.ms = 1000;
    blur(this);

    this.clock.ms = 2000;
    focus(this);
    this.clock.ms = 3000;
    blur(this);

    assert.strictEqual(this.sent.length, 1);

    this.clock.ms = 6000;
    focus(this);
    this.clock.ms = 7000;
    blur(this);

    assert.strictEqual(this.sent.length, 2);
  });

  test("always flushes the latest value on pagehide, bypassing the throttle", function (assert) {
    this.buildTracker();

    this.clock.ms = 1000;
    blur(this);

    this.clock.ms = 2000;
    focus(this);
    this.clock.ms = 3000;
    pagehide();

    assert.strictEqual(this.sent.length, 2);
    assert.strictEqual(this.sent.at(-1).engaged_seconds, 2);
  });
});
