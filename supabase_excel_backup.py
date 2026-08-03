import os
from datetime import datetime
import pandas as pd
from supabase import create_client, Client
import resend

# Environment variables (configured in GitHub Secrets)
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
RESEND_API_KEY = os.environ.get("RESEND_API_KEY")
RECIPIENT_EMAIL = os.environ.get("RECIPIENT_EMAIL")
# Optional custom sender, defaults to Resend's free onboarding sender address
SENDER_EMAIL = os.environ.get("SENDER_EMAIL", "onboarding@resend.dev")

TABLES = [
    "calls",
    "inward_repairs",
    "pricelist",
    "replacements",
    "requests",
    "sales",
    "purchases",
    "inward_estimate_items",
    "sale_items",
    "purchase_order_items",
    "app_users",
    "app_versions",
]

def fetch_all_table_data(supabase: Client, table_name: str):
    """Fetches all rows from a given table handling pagination (1000 rows max per batch)."""
    all_rows = []
    page_size = 1000
    start = 0

    while True:
        res = supabase.table(table_name).select("*").range(start, start + page_size - 1).execute()
        rows = res.data
        if not rows:
            break
        all_rows.extend(rows)
        if len(rows) < page_size:
            break
        start += page_size

    return all_rows

def generate_excel():
    print("Connecting to Supabase...")
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    
    today_str = datetime.now().strftime("%Y-%m-%d")
    file_name = f"supabase_backup_{today_str}.xlsx"

    print("Fetching tables and writing to Excel...")
    with pd.ExcelWriter(file_name, engine="openpyxl") as writer:
        for table in TABLES:
            try:
                data = fetch_all_table_data(supabase, table)
                df = pd.DataFrame(data)
                
                # Sort rows so newest entries appear at the bottom
                if not df.empty:
                    # Check for common timestamp or ID columns to order ascending
                    order_col = None
                    for col in ["created_at", "createdAt", "date", "id"]:
                        if col in df.columns:
                            order_col = col
                            break
                    
                    if order_col:
                        df = df.sort_values(by=order_col, ascending=True)
                    else:
                        # Reverse rows if default API returned newest first
                        df = df.iloc[::-1].reset_index(drop=True)

                sheet_name = table[:30]
                df.to_excel(writer, sheet_name=sheet_name, index=False)
                print(f"  ✓ Exported table '{table}' ({len(data)} rows)")
            except Exception as e:
                print(f"  ✕ Failed to export table '{table}': {e}")
                df_err = pd.DataFrame([{"error": str(e)}])
                df_err.to_excel(writer, sheet_name=table[:30], index=False)

    return file_name

def send_email_resend(file_path: str):
    print("Sending backup email via Resend API...")
    resend.api_key = RESEND_API_KEY
    
    today_str = datetime.now().strftime("%d %b %Y")
    subject = f"📊 Daily Supabase Database Backup - {today_str}"

    with open(file_path, "rb") as f:
        file_content = f.read()

    params = {
        "from": SENDER_EMAIL,
        "to": [RECIPIENT_EMAIL],
        "subject": subject,
        "html": f"""<p>Hello,</p>
<p>Attached is your daily Supabase database backup for <strong>{today_str}</strong>.</p>
<p>All tables (calls, inward_repairs, pricelist, etc.) have been exported into individual worksheet tabs within the attached Excel file.</p>
<p>Best regards,<br><strong>Automated Backup System</strong></p>""",
        "attachments": [
            {
                "filename": os.path.basename(file_path),
                "content": list(file_content),
            }
        ],
    }

    email = resend.Emails.send(params)
    print(f"✓ Backup email successfully sent via Resend API to {RECIPIENT_EMAIL}!")

if __name__ == "__main__":
    excel_file = generate_excel()
    send_email_resend(excel_file)
