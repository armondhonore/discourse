import Service, { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import {
  browserAttention,
  onBrowserAttentionChange,
  removeOnBrowserAttentionChange,
} from "discourse/lib/user-presence";

const THROTTLE_MS = 3000;
const ENGAGEMENT_PATH = "/srv/engagement";

export default class EngagementTracker extends Service {
  @service siteSettings;

  now = () => Date.now();

  transport = (body) => {
    fetch(getURL(ENGAGEMENT_PATH), {
      method: "POST",
      keepalive: true,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  };

  #sessionId;
  #engaged = false;
  #engagedStartMs = null;
  #engagedMs = 0;
  #lastSentMs = null;
  #attentionListener;
  #pagehideListener;

  willDestroy() {
    super.willDestroy(...arguments);
    this.stop();
  }

  start() {
    this.#sessionId = document.querySelector(
      "meta[name=discourse-track-view-session-id]"
    )?.content;
    if (!this.#sessionId) {
      return;
    }

    const { focused, visible } = browserAttention();
    this.#engaged = focused && visible;
    this.#engagedStartMs = this.#engaged ? this.now() : null;

    this.#attentionListener = (attention) => this.#onAttentionChange(attention);
    onBrowserAttentionChange(this.#attentionListener);

    this.#pagehideListener = () => this.#disengage({ force: true });
    window.addEventListener("pagehide", this.#pagehideListener);
  }

  stop() {
    if (this.#attentionListener) {
      removeOnBrowserAttentionChange(this.#attentionListener);
      this.#attentionListener = null;
    }
    if (this.#pagehideListener) {
      window.removeEventListener("pagehide", this.#pagehideListener);
      this.#pagehideListener = null;
    }
  }

  #onAttentionChange({ focused, visible }) {
    const engaged = focused && visible;
    if (engaged === this.#engaged) {
      return;
    }

    if (engaged) {
      this.#engagedStartMs = this.now();
      this.#engaged = true;
    } else {
      this.#disengage();
    }
  }

  #disengage({ force = false } = {}) {
    this.#bank();
    this.#engaged = false;
    this.#send({ force });
  }

  #bank() {
    if (this.#engagedStartMs !== null) {
      this.#engagedMs += this.now() - this.#engagedStartMs;
      this.#engagedStartMs = null;
    }
  }

  #send({ force = false } = {}) {
    const now = this.now();
    if (
      !force &&
      this.#lastSentMs !== null &&
      now - this.#lastSentMs < THROTTLE_MS
    ) {
      return;
    }

    this.#lastSentMs = now;
    this.transport({
      session_id: this.#sessionId,
      engaged_seconds: this.#cappedSeconds(this.#engagedMs),
    });
  }

  #cappedSeconds(ms) {
    return Math.min(
      Math.floor(ms / 1000),
      this.siteSettings.browser_pageview_max_engaged_seconds
    );
  }
}
