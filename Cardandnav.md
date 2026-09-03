Yes — I think stacked money cards are a very good option for this app, especially because your app is becoming more than an expense tracker. The cards give the user an immediate visual answer to:

“Where is my money right now?”

The key is to make them represent money accounts, not necessarily physical bank cards.

The concept

For example:

Your money
┌─────────────────────────────────────┐
│ M-Pesa                         👁   │
│                                     │
│ Available balance                   │
│ TSh 420,000                         │
│                                     │
│ 📱 Mobile Money                     │
│ •••• 4821                           │
│                                     │
│ This month  ↓ TSh 380,000           │
└─────────────────────────────────────┘
       ┌─────────────────────────────┐
       │ CRDB                         │
       │ TSh 1,850,000                │
       └─────────────────────────────┘
              ┌──────────────────────┐
              │ Cash                 │
              │ TSh 180,000          │
              └──────────────────────┘

The user swipes horizontally or vertically through the cards.

⸻

What I’d put on each card

I wouldn’t put too much information on the card. Its primary job is to show balance + identity.

1. Account name

Examples:

M-Pesa
CRDB
Cash
NMB
Visa

⸻

2. Current balance

This should be the biggest element.

TSh 420,000

I’d use Available balance rather than simply “Balance” for accounts where that distinction matters.

For cash:

Cash available

For bank:

Available balance

For credit card:

Available credit

⸻

3. Account type

Small secondary label:

Mobile Money

Bank Account

Cash

Credit Card

Savings

This helps distinguish multiple accounts.

⸻

4. Account identifier

Don’t show sensitive information.

For example:

•••• 4821

or:

M-Pesa

For a bank:

•••• 3928

For cash:

You don’t need an identifier.

⸻

5. Institution / account icon

A small logo/icon can make cards immediately recognizable.

But don’t make the card dependent on bank branding. The user’s custom account name should remain primary.

⸻

6. Money movement

This is where I’d add something interesting.

Small text at the bottom:

This month ↓ TSh 380,000

or perhaps:

In TSh 620,000 · Out TSh 380,000

But I wouldn’t show both by default if it makes the card busy.

⸻

Different account types can have different information

This is where your system can become really good.

💵 Cash

Cash
TSh 180,000
Cash wallet
This month
↓ TSh 95,000

⸻

📱 Mobile Money

M-Pesa
TSh 420,000
•••• 4821
This month
↓ TSh 380,000

⸻

🏦 Bank

CRDB
TSh 1,850,000
•••• 3928
This month
↑ TSh 1,200,000
↓ TSh 740,000

⸻

💳 Credit Card

This one should behave differently:

Visa
TSh 250,000
Available credit
Used TSh 350,000
Limit TSh 600,000

The app should not represent credit-card spending as money you currently own.

⸻

💰 Savings

Emergency Fund
TSh 2,400,000
Savings
+ TSh 200,000 this month

⸻

The card itself should be tappable

Tap the M-Pesa card:

M-Pesa

TSh 420,000

Then:

Money in              TSh 620,000
Money out             TSh 380,000
Transfers             TSh 200,000
Expenses              TSh 180,000

And transaction history:

Today
− TSh 35,000
TotalEnergies
Fuel
Yesterday
− TSh 8,000
Lunch
Eating Out
Aug 30
+ TSh 200,000
Income
Aug 28
+ TSh 100,000
CRDB → M-Pesa
Transfer

So the card becomes a gateway into the account, rather than just decoration.

⸻

The stacked design is particularly useful

I actually prefer this over a normal list of accounts for your app.

Instead of:

Cash             TSh 180,000
M-Pesa           TSh 420,000
CRDB             TSh 1,850,000
NMB              TSh 700,000

you get something visually memorable:

┌───────────────────────────────┐
│ M-Pesa                        │
│                               │
│ TSh 420,000                   │
│                               │
│ Mobile Money       ••••4821   │
└───────────────────────────────┘
   ┌───────────────────────────┐
   │ CRDB                      │
   │ TSh 1,850,000             │
   └───────────────────────────┘
      ┌────────────────────────┐
      │ Cash                   │
      │ TSh 180,000            │
      └────────────────────────┘

It makes the home page feel more like a personal financial dashboard.

⸻

But I would add one thing above the cards

Total money

Something like:

Your money

TSh 2,450,000

3 accounts

Then the stacked cards underneath.

This gives you two levels:

Total financial position

↓

Where the money is

↓

What happened to it

⸻

And the cards should connect directly to your command bar

This is where your whole concept starts coming together.

User opens the + command bar and says:

Spent 50,000 on fuel from M-Pesa

The app creates:

Expense
TSh 50,000
Fuel
M-Pesa

Then M-Pesa automatically changes:

TSh 420,000 → TSh 370,000

⸻

User says:

Move 200,000 from CRDB to M-Pesa

The cards update:

CRDB

TSh 1,850,000 → TSh 1,650,000

M-Pesa

TSh 370,000 → TSh 570,000

Total money remains exactly the same.

⸻

User says:

I lent John 100,000 from cash

Cash:

TSh 180,000 → TSh 80,000

But the app also creates:

John owes you TSh 100,000

That’s why I think the account-card concept is worth implementing now, because it gives the rest of your financial model somewhere to live.

⸻

One design decision I’d make

Don’t force the cards to look exactly like real bank cards.

Use the stacked-card visual metaphor, but make them feel like digital money cards.

That gives you freedom to have:

Cash → M-Pesa → CRDB → Savings → Credit Card → Business Account

all within one consistent component.

And I would make the card visually beautiful—dark, subtle gradients, slight texture/glow, large balance, minimal information—while keeping the surrounding Home screen light and clean like your current design.

So yes: I’d adopt the stacked cards. They can become one of the defining visual elements of the app rather than just another account list.

Yes — I think the dynamic bottom navigation is a very good direction for this app. I couldn’t reliably load the Pinterest short link itself, so I don’t want to pretend I’ve seen the exact interaction in that pin.  

Based on the app we’ve been designing, I’d make the navigation context-aware rather than permanently fixed.

The idea

Instead of always showing:

Home · Expenses · + · Analytics · Planner

the bottom bar can change based on what the user is currently doing.

For example, on Home:

Home · Money · ＋ · Analytics · Planner

When the user opens Expenses:

Back · Filters · ＋ · Search · More

When they open an M-Pesa account:

Overview · Transactions · ＋ · Analytics · More

And when the command bar is active, the bottom navigation can transform/disappear so the command interface becomes the focus.

Even better: the center action stays universal

The middle button remains the most important interaction:

＋

Tap it → compact command bar appears.

But the command bar can understand:

5000 lunch

→ Expense

500000 salary

→ Income

100000 to M-Pesa

→ Transfer

I lent John 100000

→ Loan out

John paid me 50000

→ Receivable repayment

How much did I spend on fuel?

→ Analytics

If I spend 5000 every day on lunch...

→ Planner

So the navigation doesn’t need to expose every possible action.

⸻

I would also make the navigation respond to the selected object

For example, tap your stacked M-Pesa card.

The bottom bar could morph into:

Overview | Transactions | + | Insights | More

Tap John from your loans:

Overview | Activity | + | Repay | More

Tap Fuel:

Overview | Expenses | + | Trends | More

This makes the app feel much more like an operating system for your money rather than a collection of separate screens.

The overall architecture becomes

                    HOME
                      │
          ┌───────────┴───────────┐
          │                       │
      Your Money               Spending
          │                       │
   ┌──────┼──────┐          Categories
   │      │      │
 Cash   M-Pesa  Bank
   │      │      │
   └──────┼──────┘
          │
       Account
       details
          │
    Transactions

And the bottom navigation adapts to wherever the user is.

I would definitely include this in the Cursor spec as a Dynamic Navigation System, alongside the stacked account cards and universal command bar.