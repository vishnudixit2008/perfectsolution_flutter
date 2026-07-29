# Project Hand-Off & Context Document: Perfect Solution Shop Management System

This document captures all business logic, technical architecture, feature modules, data models, appsheet research, screenshot paths, and code files for the **Perfect Solution** shop management application. Share this document with any incoming AI agent to instantly bring it up to speed.

---

## 🛠️ 1. Technical Architecture & Tech Stack

The application is built as a premium, highly responsive cross-platform Flutter application (optimized for Web and Android) using a clean, layered architecture:

* **Presentation Layer (UI):** Modular feature folders containing views and view-models. Uses a custom dark glassmorphic neon design system defined in [app_theme.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/core/app_theme.dart).
* **State Management:** `Provider` (`ChangeNotifier`) for reactive UI updates.
* **Business Logic (ViewModels):** Decoupled controllers managing filtering, sorting, resizable grid states, pagination, and data entry forms.
* **Data Repository:** [shop_repository.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/repositories/shop_repository.dart) abstracts all data fetch/save operations from view-models.
* **Local Database Service:** [local_database_service.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/services/local_database_service.dart) parses local JSON assets and caches active transactions using **Hive** local storage boxes.

---

## 📂 2. Complete File Directory (Key Paths)

### Core & Navigation
* **App Entrypoint:** [main.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/main.dart)
* **Design Tokens / Theme:** [app_theme.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/core/app_theme.dart)
* **Main UI Container & Sidebar:** [main_navigation_container.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/navigation/main_navigation_container.dart)
* **Cross-Module Navigation Coordinator:** [navigation_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/navigation/navigation_view_model.dart)

### Data Layer (Models)
* **Catalog Item:** [pricelist_item.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/pricelist_item.dart)
* **Sales Record:** [sale.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/sale.dart) & [sale_item.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/sale_item.dart)
* **Technician Calls:** [call_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/call_model.dart)
* **Inward Repairs:** [inward_repair.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/inward_repair.dart) & [inward_estimate_item.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/inward_estimate_item.dart)
* **Replacements:** [replacement.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/replacement.dart)
* **Customer Pre-Orders (Requests):** [request_order.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/request_order.dart)
* **Stock-In Purchases:** [purchase_order.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/purchase_order.dart) & [purchase_order_item.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/models/purchase_order_item.dart)

### Feature Modules (UI & ViewModels)
* **Sales / POS Billing:**
  * View: [sales_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/sales/views/sales_view.dart)
  * ViewModels: [sales_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/sales/view_models/sales_view_model.dart) & [recent_sales_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/dashboard/view_models/recent_sales_view_model.dart)
* **Pricelist (Stock Catalog):**
  * View: [pricelist_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/pricelist/views/pricelist_view.dart)
  * ViewModel: [pricelist_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/pricelist/view_models/pricelist_view_model.dart)
* **Inward Repairs:**
  * View: [inward_repairs_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/inward_repairs/views/inward_repairs_view.dart)
  * ViewModel: [inward_repairs_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/inward_repairs/view_models/inward_repairs_view_model.dart)
* **Replacements:**
  * View: [replacements_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/replacements/views/replacements_view.dart)
  * ViewModel: [replacements_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/replacements/view_models/replacements_view_model.dart)
* **Requests (Pre-orders):**
  * View: [requests_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/requests/views/requests_view.dart)
  * ViewModel: [requests_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/requests/view_models/requests_view_model.dart)
* **Purchases (Stock-In):**
  * View: [purchases_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/purchases/views/purchases_view.dart)
  * ViewModel: [purchases_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/purchases/view_models/purchases_view_model.dart)
* **Calls Logs:**
  * View: [calls_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/calls/views/calls_view.dart)
  * ViewModel: [calls_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/calls/view_models/calls_view_model.dart)
* **Settings:**
  * View: [settings_view.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/settings/views/settings_view.dart)
  * ViewModel: [settings_view_model.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/ui/features/settings/view_models/settings_view_model.dart)

---

## 📊 3. AppSheet Research & Knowledge Base

Below is the full breakdown of findings, list fields, input structures, and screenshot locations gathered from the AppSheet prototype.

### 1. Calls
* **Purpose:** Tracks service calls or customer inquiries assigned to technicians.
* **List Columns:** Date, Name, Mobile no., Address, Query, Assigned to, Estimate, Status, Photo 1, Photo 2, Notes.
* **Form Inputs:** Date (datetime), Name (textbox, required), Mobile no. (textbox), Address (textbox), Query (textbox), Assigned to (combobox, required), Estimate (multiline textbox), Status (combobox, default: "Pending"), Photo 1 (file), Photo 2 (file), Notes (multiline textbox).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/calls_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/calls_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/calls_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/calls_form.png)

### 2. Inward Repairs (Inward)
* **Purpose:** Logs items/devices received from customers for diagnostics or repair.
* **List Columns:** Date, Job No., Name, Mobile no., Devices, Query, Estimate items, Purchased from, Status, Notes, Photo 1.
* **Form Inputs:** Date (datetime), Job No. (textbox, read-only/auto-increment), Name (textbox), Mobile no. (textbox), Devices (textbox), Query (textbox), Estimate items (inline builder sub-table), Purchased from (multiline textbox), Status (combobox), Notes (multiline textbox), Photo 1 (file).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/inward_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/inward_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/inward_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/inward_form.png)

### 3. Replacement
* **Purpose:** Manages device or part replacements under warranty/claims.
* **List Columns:** Date, Job No., Name, Mobile No., Item, Assigned to, Deposit Date, Receive Date, Status, Photo.
* **Form Inputs:** Date (date), Job No. (textbox, read-only/auto-generated 'Z' prefix), Name (textbox), Mobile No. (textbox), Item (textbox), Assigned to (combobox), Deposit Date (date), Receive date (date), Status (combobox), Photo (file).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/replacement_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/replacement_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/replacement_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/replacement_form.png)

### 4. Price List
* **Purpose:** Catalog of items/parts along with dynamic stock status.
* **List Columns:** ITEM, category, Cash Price, Incl. GST Price, Item description, Sales history.
* **Form Inputs:** ITEM (textbox, required), category (combobox, required), Cash Price (number), Incl. GST Price (textbox, read-only), Item description (multiline textbox).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/price_list_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/price_list_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/price_list_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/price_list_form.png)

### 5. Request (Pre-Orders)
* **Purpose:** Captures custom orders or requests for special items not currently in catalog.
* **List Columns:** Date, Customer name, Mobile no., Item, Advance, Total amount, Dealer name, Status.
* **Form Inputs:** Date (date), Customer name (textbox), Mobile no. (textbox), Item (textbox), Advance (number), Estimate (textbox), Total amount (number), Photo (file), Dealer name (textbox), Status (combobox).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/request_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/request_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/request_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/request_form.png)

### 6. Sales
* **Purpose:** Records custom transactions and checkout state.
* **List Columns:** Customer Name, Customer Number, Payment Mode, Advance, Discount, Order Status.
* **Form Inputs:** Customer Name (textbox), Customer Number (textbox), Payment Mode (combobox), Advance (number), Discount (number), Order Status (combobox).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/sales_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/sales_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/sales_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/sales_form.png)

### 7. Purchase (Stock In)
* **Purpose:** Logs inbound inventory shipments from distributors.
* **List Columns:** Date, Purchased from, Stock in items, Total Amount, Status, Notes.
* **Form Inputs:** Date (datetime), Purchased from (combobox), Stock in items entries (sub-list builder), Total Amount (read-only sum), Status (PENDING/CONFIRMED), Notes (multiline textbox).
* **Screenshots:**
  * Grid List: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/purchase_list.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/purchase_list.png)
  * Add Form: [/Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/purchase_form.png](file:///Users/vishnudixit/.gemini/antigravity/brain/9fd47011-de64-41eb-b8ed-a6c6ef35b2a2/purchase_form.png)

---

## ⚙️ 4. Business Logic & Integration Rules

### 1. Unified Detail Dialog Actions & Navigation Pre-filling
Cross-module transitions (e.g. converting a Call, Inward job, or Request to a POS Sale) are managed via `NavigationViewModel`. When a user initiates a transition:
1. Prefill data containing name, phone, items, or device specs is saved to the coordinator.
2. The active navigation tab switches.
3. The target view loads, reads and populates its text controllers, and immediately clears the prefill queue.

### 2. Auto-Increment Seeds (Hive level)
* **Inward Repairs:** The database automatically assigns numeric job numbers starting at **`4111`**.
* **Replacements:** Assigned alphanumeric job numbers starting at **`Z223`** (e.g., Z223, Z224...).
* **Requests & Purchases:** Uses auto-generated alphanumeric unique IDs (derived from timestamps).

### 3. Dynamic WhatsApp Receipts
Mobile phone numbers are sanitized (stripping formatting, prepending `91` country code if none exists). The system generates and triggers a URL in the browser (using `wa.me`).
* **Inward Repairs Receipt Template:**
  > *"Hello [Name], We have received your [Device], Job no. of your device is [JobNo]. Our team is thoroughly working to diagnose and resolve the problem. We will provide you with a timely update once the issue has been addressed. Thank you for your cooperation. Perfect Solution"*

### 4. Stock Integration Rules (Purchase Orders)
* Adding line-items inside **Purchases (Stock-In)** pulls up autocomplete options matching the active **Pricelist** catalog.
* Toggling a Purchase Order status to `CONFIRMED` increments the product quantities directly in the active **Pricelist** catalog.
* Reverting a confirmed Purchase to `PENDING` (or deleting it) decrements the quantities back.

### 5. Sales & Invoicing Engine
* **A5 PDF Print:** Generates high-quality vector A5 portrait printouts. Replaces unicode `₹` symbols with `Rs.` to avoid PDF library font exceptions.
* **Vector QR Codes:** Automatically paints:
  1. A Google Reviews code directing to `https://g.page/r/CaqZxhuvkW-7EBM/review`.
  2. A dynamic UPI QR code that maps the active UPI ID chosen in Settings, leaving the payee name (`pn`) parameter empty to allow scanning apps (GPay, PhonePe, Paytm) to resolve the verified target name dynamically.

### 6. UI Preferences & Table Column Persistence
* **Service:** [ui_preferences_service.dart](file:///Users/vishnudixit/.gemini/antigravity/scratch/shop_management_flutter/lib/data/services/ui_preferences_service.dart)
* **Hive Box:** `ui_preferences`
* **Behavior:** Stores customized column widths for all data tables (`calls`, `inward`, `replacement`, `requests`, `purchases`). Resizing any table column header immediately persists the width locally and restores it automatically across app restarts.

---

## 📋 5. Recent Work & Active Task List

### Recent Work Completed
* **Calls Page Polish**:
  - Resized header font to compact size matching Inward Repairs.
  - Removed extra actions column; kept clean clickable rows opening resizable detail modal.
  - Status priority sorting applied (Pre-complete → Pending → Pending payment → Complete).
* **Column Width Persistence**:
  - Integrated `UiPreferencesService` in `main.dart` and attached live persistence across Calls, Inward Repairs, Replacements, Special Requests, and Purchase Ledger views.

### Current Active Tasks & Backlog
- [x] Create UI Preferences Service (`ui_preferences_service.dart`) to store column widths in Hive box.
- [x] Persist column widths in `CallsView`.
- [x] Persist column widths in `InwardRepairsView`.
- [x] Persist column widths in `ReplacementsView`.
- [x] Compile fresh release web version with all latest UI updates and serve locally (`http://localhost:8080`).
- [x] Compile release APK and deploy wirelessly to device (`192.168.1.35:33065` - Package `com.perfectsolution.shop_management_flutter`). Verified: Streamed Install Success & App Launched on Device.
- [x] Build native macOS Desktop app (`shop_management_flutter.app`) via Xcode toolchain and launch on macOS screen (`open build/macos_build/Build/Products/Release/shop_management_flutter.app`).
- [ ] Add Excel Data Seeding helper (`seedCallsFromExcel`) for Excel file (`Perfect Solution (1).xlsx`).

---

## 🚀 6. How to Build, Run & Deploy

### Compilation & Web Hosting (Release Mode)
1. Build the release package:
   ```bash
   flutter build web --release
   ```
2. Serve the production bundle from the compiled folder:
   ```bash
   cd build/web
   python3 -m http.server 8080
   ```
3. Open `http://localhost:8080` in any browser to preview the app.

### Connect & Install on Android via Wireless Debugging
1. Pair your device:
   ```bash
   ~/Library/Android/sdk/platform-tools/adb pair 192.168.1.35:<PAIRING_PORT> <PAIRING_CODE>
   ```
2. Establish connection:
   ```bash
   ~/Library/Android/sdk/platform-tools/adb connect 192.168.1.35:<CONNECTION_PORT>
   ```
3. Compile the release APK:
   ```bash
   flutter build apk --release
   ```
---

## 🛠️ 7. Verified Fixes Round (Items 1 - 8)

The following UI bugs and regressions were systematically refactored, built into a production release APK, installed via Wireless ADB (`192.168.1.35`), and visually verified via ADB screenshots (`/tmp/shop-ui-verify.png`):

1. **Floating Pagination Island (`AppPaginationBar`)**:
   - Converted `AppPaginationBar` into a compact left-aligned floating pill (`< 1/26 >`) so it sits on the bottom-left and never overlaps or competes with the floating `+` FAB on the bottom-right.
2. **Popup Menu Anchor Position (`AppListCard`)**:
   - Added `position: PopupMenuPosition.under` to `PopupMenuButton` in `AppListCard` so overflow edit/delete menus anchor cleanly under the `⋮` icon without obscuring card status badges.
3. **Single Save Button per Form**:
   - Audited all create/edit form dialogs ("Log Call", "Add Inward Repair", "Add Replacement", "Add Product", "Add Request", "Add Purchase") and removed duplicate bottom save buttons, standardizing on the top app-bar save action.
4. **Pricelist Read-Only Detail View**:
   - Created `_showDetailPopup` bottom sheet for Pricelist items. Tapping a product row now opens product details (with Edit & Delete options) instead of entering edit mode directly.
5. **Invoice Detail Action Buttons Layout**:
   - Redesigned invoice detail action buttons in `SalesView` into a clean 2-row layout (`Verify & Deduct Stock` / `Mark as Pending` on row 1, `Print Receipt` + `Delete` on row 2) so text never wraps vertically on mobile widths.
6. **Single-Tap Keyboard Focus on Search Bar**:
   - Added `FocusNode` with auto-focus callback to `AppSearchFilterBar` so tapping the collapsed search field opens the keyboard immediately on the first tap.
7. **Wired Filter Icon (`AppSearchFilterBar`)**:
   - Connected the search bar tune/filter icon to toggle the filter options bar across all list screens.
8. **High-Contrast Switch Styling**:
   - Upgraded the "Custom Name" toggle switch in `PurchasesView` with high-contrast active/inactive styling and clear "Custom Name" vs "Catalog Select" badge labels.


