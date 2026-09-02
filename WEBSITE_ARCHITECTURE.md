# Website Architecture & Deployment Guide for Developers & AI Agents

> **Project:** Perfect Solution Noida — Official Business Website  
> **Production URL:** [https://perfectsolutionnoida.in](https://perfectsolutionnoida.in)  
> **Hosting Provider:** Cloudflare Pages (Connected to GitHub CI/CD)  
> **Edge Network:** Cloudflare Global Anycast CDN (Delhi/Noida Edge)

---

## 1. Overview & Infrastructure

The official website for **Perfect Solution Noida** is hosted on **Cloudflare Pages** and automatically synchronizes with its source code repository on **GitHub**.

* **Live Domain:** `https://perfectsolutionnoida.in` and `https://www.perfectsolutionnoida.in`
* **Auto-Deployment Engine:** Every `git push` to the `main` branch triggers an automated Cloudflare Pages deployment that updates the website across all 330+ global edge data centers in under **15 seconds**.
* **Zero Server Dependency:** The website runs on Cloudflare's serverless edge cloud. It remains online **24/7/365 with 100% uptime**, even when the shop Linux PC or local server is turned off.

---

## 2. Source Code Repository

| Property | Value |
|---|---|
| **GitHub Repository** | `https://github.com/perfectsolutionnoida/perfectsolutionnoida.github.io` |
| **Primary Branch** | `main` |
| **Build System** | Static HTML / CSS / Vanilla JS |
| **Publish Directory** | `/` (Root directory) |

---

## 3. How Future AI Agents & Developers Should Make Updates

Whenever you or another AI agent need to update the website (e.g., adding services, updating shop contact info, changing banners, or modifying styles):

### Step-by-Step Workflow:

1. **Clone or Pull the Latest Website Repository:**
   ```bash
   git clone https://github.com/perfectsolutionnoida/perfectsolutionnoida.github.io.git
   cd perfectsolutionnoida.github.io
   git pull origin main
   ```

2. **Make the Desired Edits:**
   * `index.html`: Main landing page, navigation, repair service offerings, shop address, contact numbers, and WhatsApp links.
   * `css/` or `styles/`: Responsive layouts, typography, theme colors, and animations.
   * `js/` or `scripts/`: Interactive components, repair job tracking widgets, or modals.
   * `images/` or `assets/`: Logos, shop photos, service banners.

3. **Test the Changes Locally:**
   You can preview the website locally using any lightweight local server:
   ```bash
   # Using Python 3:
   python3 -m http.server 8080
   # Then open http://localhost:8080 in your browser
   ```

4. **Commit & Push to GitHub:**
   ```bash
   git add .
   git commit -m "Update shop services and landing page design"
   git push origin main
   ```

5. **Automatic Global Deployment:**
   * The moment `git push` completes, Cloudflare Pages automatically detects the commit.
   * Within **10–15 seconds**, the new changes go live globally at `https://perfectsolutionnoida.in`.
   * **No manual build or upload steps are required.**

---

## 4. Subdomains & Network Topology

| Subdomain / URL | Destination | Infrastructure |
|---|---|---|
| **`https://perfectsolutionnoida.in`** | Official Public Website | Cloudflare Pages (24/7/365 Edge CDN) |
| **`https://www.perfectsolutionnoida.in`** | Official Public Website (www alias) | Cloudflare Pages |
| **`https://api.perfectsolutionnoida.in`** | Flutter App Supabase Backend API | Cloudflare Tunnel (`cloudflared`) ➔ Local Shop Server (`localhost:8000`) |
| **`http://100.123.9.102:3000`** | Admin Database Studio | Private Tailscale Encrypted Mesh |

---

## 5. Key Rules for Developers & AI Agents

1. **Do Not Break API Routing:**  
   `api.perfectsolutionnoida.in` is reserved exclusively for the shop management app's Supabase backend tunnel. Do not create DNS records that conflict with `api`.
2. **Responsive Mobile-First Design:**  
   The website is primarily visited by mobile customers in Noida/Delhi NCR looking for repairs. Ensure all buttons (especially **"Call Now"** and **"WhatsApp Inquiry"**) remain easily tappable on mobile devices.
3. **Preserve SEO Meta Tags:**  
   Maintain proper OpenGraph tags, page titles, schema markup, and Google Local Business metadata for Noida search rankings.
