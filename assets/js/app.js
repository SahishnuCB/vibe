// assets/js/app.js

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/vibe"
import topbar from "../vendor/topbar"

// -----------------------------
// Helpers
// -----------------------------
function nowMs() {
  return Date.now()
}

function loadYouTubeIframeAPI() {
  // Load once, share a promise
  if (window.__ytApiPromise) return window.__ytApiPromise

  window.__ytApiPromise = new Promise((resolve) => {
    // If already present
    if (window.YT && window.YT.Player) return resolve(window.YT)

    // YouTube calls this global when ready
    const prev = window.onYouTubeIframeAPIReady
    window.onYouTubeIframeAPIReady = function () {
      if (typeof prev === "function") prev()
      resolve(window.YT)
    }

    // Inject script if not injected
    const existing = document.querySelector('script[src="https://www.youtube.com/iframe_api"]')
    if (!existing) {
      const tag = document.createElement("script")
      tag.src = "https://www.youtube.com/iframe_api"
      document.head.appendChild(tag)
    }
  })

  return window.__ytApiPromise
}

// -----------------------------
// Hooks
// -----------------------------
const Hooks = {}

// Auto-scroll chat when server tells us to
Hooks.AutoScroll = {
  mounted() {
    this.handleEvent("scroll_chat", () => {
      this.el.scrollTop = this.el.scrollHeight
    })
  },
}

// YouTube player hook
Hooks.YouTubePlayer = {
  mounted() {
    this.ready = false
    this.player = null
    this.lastPlayback = null
    this.pendingLoad = null

    this.playerEl = this.el.querySelector("#yt-player")
    if (!this.playerEl) {
      console.warn("[YT] #yt-player not found inside hook root")
      return
    }

    // Wire buttons (inside yt-root)
    this.btnPlay = this.el.querySelector('[data-yt="play"]')
    this.btnPause = this.el.querySelector('[data-yt="pause"]')
    this.btnResync = this.el.querySelector('[data-yt="resync"]')

    if (this.btnPlay) this.btnPlay.addEventListener("click", () => this.play())
    if (this.btnPause) this.btnPause.addEventListener("click", () => this.pause())
    if (this.btnResync) this.btnResync.addEventListener("click", () => this.resync())

    // Server -> client: load a new video (when you click a result)
    this.handleEvent("player_load", (payload) => {
      this.lastPlayback = payload
      this.load(payload)
    })

    // Server -> client: sync event (play/pause/seek from other side)
    this.handleEvent("player_sync", (payload) => {
      this.lastPlayback = payload
      this.applyPlayback(payload)
    })

    // Create the player lazily
    this.ensurePlayer()
  },

  destroyed() {
    try {
      if (this.player && typeof this.player.destroy === "function") {
        this.player.destroy()
      }
    } catch (_) {}
    this.player = null
    this.ready = false
  },

  // -----------------------------
  // Core guards
  // -----------------------------
  canUsePlayer() {
    return (
      this.player &&
      this.ready === true &&
      typeof this.player.playVideo === "function" &&
      typeof this.player.pauseVideo === "function"
    )
  },

  ensurePlayer() {
    // Don’t create twice
    if (this.player) return

    loadYouTubeIframeAPI()
      .then(() => {
        // YouTube API ready, create player
        this.player = new window.YT.Player(this.playerEl, {
          // NOTE: keep initial blank; we load via loadVideoById later
          host: "https://www.youtube.com",
          playerVars: {
            autoplay: 0,
            playsinline: 1,
            rel: 0,
            modestbranding: 1,
            origin: window.location.origin, // reduces postMessage mismatch warnings
          },
          events: {
            onReady: () => {
              this.ready = true

              // If something arrived before onReady, apply it now
              if (this.pendingLoad) {
                const p = this.pendingLoad
                this.pendingLoad = null
                this.load(p)
              } else if (this.lastPlayback) {
                // If we already have state, sync to it
                this.applyPlayback(this.lastPlayback)
              }
            },

            onStateChange: (e) => {
              // 1 = playing, 2 = paused
              if (!this.canUsePlayer()) return

              const state = e.data
              if (state !== 1 && state !== 2) return

              let posSec = 0
              try {
                posSec = this.player.getCurrentTime()
              } catch (_) {}

              const payload = {
                is_playing: state === 1,
                position_ms: Math.floor(posSec * 1000),
                sent_at_ms: nowMs(),
              }

              // Send up to server (server broadcasts to the other client)
              this.pushEvent("player_event", payload)
            },
          },
        })
      })
      .catch((err) => {
        console.error("[YT] Failed to load iframe api", err)
      })
  },

  // -----------------------------
  // Actions
  // -----------------------------
  load(p) {
    // If player not ready yet, queue
    if (!this.player || !this.ready) {
      this.pendingLoad = p
      this.ensurePlayer()
      return
    }
    if (!p || !p.video_id) return

    const startSec = Math.max(0, (p.position_ms || 0) / 1000)

    // loadVideoById(videoId, startSeconds)
    try {
      this.player.loadVideoById(p.video_id, startSec)
      if (!p.is_playing) this.player.pauseVideo()
    } catch (e) {
      console.warn("[YT] loadVideoById failed (not ready yet?)", e)
    }
  },

  applyPlayback(p) {
    if (!this.canUsePlayer()) return
    if (!p || !p.video_id) return

    // If different video, force load
    const currentId = this.safeVideoId()
    if (currentId && currentId !== p.video_id) {
      this.load(p)
      return
    }

    // Compute expected position using sent_at_ms (basic drift correction)
    const expectedMs = (p.position_ms || 0) + (nowMs() - (p.sent_at_ms || nowMs()))
    const seekSec = Math.max(0, expectedMs / 1000)

    try {
      if (p.is_playing) {
        // ✅ Fix 1: only seek if drift is BIG (prevents constant rebuffering)
        const currentSec = this.player.getCurrentTime?.() ?? 0
        const drift = Math.abs(currentSec - seekSec)

        if (drift > 1.2) {
          this.player.seekTo(seekSec, true)
        }

        this.player.playVideo()
      } else {
        // ✅ Fix 2: don't seek on pause (seeking on pause causes extra buffering)
        this.player.pauseVideo()
      }
    } catch (e) {
      console.warn("[YT] applyPlayback failed", e)
    }
  },


  safeVideoId() {
    try {
      const data = this.player.getVideoData?.()
      return data && data.video_id ? data.video_id : null
    } catch (_) {
      return null
    }
  },

  play() {
    if (!this.canUsePlayer()) return
    try {
      this.player.playVideo()
    } catch (_) {}
  },

  pause() {
    if (!this.canUsePlayer()) return
    try {
      this.player.pauseVideo()
    } catch (_) {}
  },

  resync() {
    // Prefer syncing to last known shared state
    if (this.lastPlayback) {
      this.applyPlayback(this.lastPlayback)
      return
    }

    // Fallback: publish current state as a player_event
    if (!this.canUsePlayer()) return
    try {
      const posSec = this.player.getCurrentTime()
      const state = this.player.getPlayerState()
      const isPlaying = state === 1

      this.pushEvent("player_event", {
        is_playing: isPlaying,
        position_ms: Math.floor(posSec * 1000),
        sent_at_ms: nowMs(),
      })
    } catch (_) {}
  },
}

// -----------------------------
// LiveSocket + Topbar
// -----------------------------
const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, ...Hooks },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

// Connect if there are LiveViews on the page
liveSocket.connect()

// Expose for debugging in console
window.liveSocket = liveSocket
