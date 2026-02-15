# Vibe

Real-time shared media synchronization experiment built with Elixir and Phoenix LiveView.

Vibe is a server-authoritative room system where two connected clients watch the same YouTube track in sync. When one user plays, pauses, or (later) seeks, the other client reflects the change instantly. A live chat runs alongside the synchronized playback state.

---

## 🚀 What This Project Explores

- Real-time event-driven coordination
- Shared state convergence across clients
- Phoenix PubSub broadcasting
- Server-authoritative playback control
- LiveView reactive UI without a heavy SPA
- Media sync + chat coexistence in a single room model

This is not just a “watch together” app — it is a distributed state synchronization experiment.

---

## 🧠 Architecture Overview

### Conceptual Event Flow

```
Client A (play/pause/chat)
  → LiveView event handler
    → Room state update (authoritative)
      → Phoenix PubSub broadcast
        → Client B updates UI + playback
```

### Key Components

- **Phoenix LiveView** – Handles real-time UI updates  
- **Phoenix PubSub** – Broadcasts room state changes  
- **Room process** – Maintains canonical playback + chat state  
- **YouTube API integration** – Handles search and video playback embedding  

The server resolves user intent into canonical room state. Clients converge toward that state.

---

## 🛠 Tech Stack

- Elixir  
- Phoenix  
- Phoenix LiveView  
- Phoenix PubSub  
- WebSockets  
- YouTube Data API  

---

## ⚙️ Setup & Running Locally

### 1️⃣ Clone the repository

```bash
git clone https://github.com/SahishnuCB/vibe.git
cd vibe
```

### 2️⃣ Create environment variables

Create a `.env` file (not committed) based on `.env.example`:

```env
SECRET_KEY_BASE=generate_with_mix_phx_gen_secret
DATABASE_URL=ecto://postgres:postgres@localhost/vibe_dev
YOUTUBE_API_KEY=your_youtube_api_key_here
```

Generate a secret key:

```bash
mix phx.gen.secret
```

### 3️⃣ Install dependencies

```bash
mix setup
```

### 4️⃣ Start the server

```bash
mix phx.server
```

Visit:

```
http://localhost:4000
```

---

## 🔮 Roadmap

- Seek synchronization + drift correction  
- Multi-user room support  
- Presence indicators  
- Event ordering conflict handling  
- Basic observability (metrics/logging)  
- Optional room state persistence  

---

## 📚 Why This Exists

Vibe was built as a hands-on experiment in coordinating shared state across multiple clients in real time.

It explores how systems behave under:

- Network latency  
- Rapid event changes  
- Competing user input  
- Event ordering constraints  

---

## 📄 License

MIT
