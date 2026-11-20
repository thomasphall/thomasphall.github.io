---
title: "One Bot per Domain: Running My Personal Life on Grok Bot"
description: >-
  How I split my personal admin across a fleet of Grok Bot agents, one per
  life domain, with a router in front, what actually worked, where it broke,
  and the guardrails I'd keep if I started over.
date: 2026-11-20 09:00:00 -0600
categories: [AI, Productivity]
tags: [grok-bot, ai-agents, automation, personal-productivity]
permalink: /posts/grok-bot-personal-life/
social_title: |-
  One bot
  per domain
social_label: Personal automation
social_subtitle: Router · Routines · Approvals
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. This is not a sponsored post.
> Everything below is from my own use over the last few months; I've
> stripped out names, accounts, amounts, and anything else personal.
{: .prompt-info }

I spend my workdays telling customers to stop running everything on one big
cluster with one big admin account. Split by blast radius, give each workload
only the access it needs, automate the boring parts, and keep a human on the
approve button for anything that can't be rolled back.

A few months ago I realized my personal life was the opposite of that. One
inbox, one calendar, a pile of portals, and me as the only operator. So I
did what I'd tell a customer to do and broke it up. I now run a small fleet of
Grok Bot agents, one per life domain, with a general-purpose bot in front that
routes work to the right specialist.

This post covers what that looks like, what it actually got done, where it
fell over, and what I'd do differently. It's not a product review. Some of
the most useful moments came from the bots telling me what they couldn't do.

## The architecture: a router and a set of specialists

The shape is a hub and spokes. The main bot, plain "Grok Bot", is where I
type most things. It answers directly when it can, and when the work belongs
to a domain it hands it to that domain's bot, either by messaging the bot or
by having me talk to it directly.

Here's the inventory, written the way I'd write it if it lived in a Git repo:

```yaml
fleet:
  router:
    name: Grok Bot
    role: front door, cross-domain questions, hands off to specialists
  specialists:
    - name: Email        # weekday morning inbox triage, drafts replies
    - name: Calendar     # Google Calendar reads and writes
    - name: Bills        # utility, phone, and service bills
    - name: Finance      # accounts, spending, investments (read-mostly)
    - name: Home         # house records, insurance, warranties, vendors
    - name: Medical      # appointments, portals, paperwork
    - name: Tickets      # event tickets, resale, conflict checks
    - name: Music        # taste analysis, show and festival picks
    - name: Travel       # flights, hotels, credits
    - name: Buy/Sell     # marketplaces, price checks, listings
    - name: Blog         # ideas, drafts, and PRs for this site
  connectors: [Gmail, Google Calendar, Google Drive, Google Docs, Plaid (read-only), X, GitHub]
  secrets: vault       # logins live there, not in chat
  approvals: required  # anything sent, posted, bought, or deleted
```

Why many bots instead of one? The same reasons you'd split workloads on a
cluster:

- **Context stays clean.** The Home bot knows the house, the insurance
  history, and the vendors. It doesn't need my concert history, and the
  Tickets bot doesn't need my mortgage.
- **Memory is scoped.** Each bot keeps notes about its own domain, so a
  question like "is the house still under the builder warranty?" gets
  answered from records that bot already gathered, not from a cold start.
- **Routines have an owner.** Every scheduled job lives on the bot that
  owns the domain, so I know where to go when one needs to change.

## What the specialists actually did

I'm only including things that happened. Details are generalized.

### Email: the morning brief

The Email bot runs a weekday morning inbox check. It reads the overnight
mail and sends me a short note: what needs a reply, what looks like a scam,
which security notices I should confirm were me, and anything with a
deadline. Most mornings the answer is "nothing urgent," and that's the
point. I stopped opening my inbox to find out whether something was on fire.

It also drafts replies when I ask. When a home cleaning service billed me
well above its own written quote, I said "email them and ask why." The bot
pulled the quote and the receipt, wrote a reply on the original thread that
laid out the gap and asked for an itemized breakdown and a refund, and showed
me the draft. I hit send. It then watched for the response in the morning
brief.

### Bills: the portal migration trap

I asked the Bills bot to pay a utility bill. The old portal showed a zero
balance, which would have been the end of it for me. The bot noticed that
the bills had moved to a new billing system months earlier, opened the PDF,
and found two earlier bills that had never been paid because they went to a
portal I didn't know existed. It registered the new account with a password
generated in the vault, showed me the real total before charging anything,
paid it after I said yes, and then set up AutoPay.

For the AutoPay step it needed bank details. It didn't ask me to paste them
in chat. It put up a secure form, the values went straight into the portal,
and the bot said plainly that it never saw them. That's the right pattern.

The same bot helped me push my phone carrier for a better rate. It broke
down what I was actually paying for the plan versus a device payment, which
made the comparison with cheaper carriers honest. The carrier said no to a
match and offered a plan review instead. More on what happened next in the
failure section.

### Finance: read-only and skeptical

The Finance bot links accounts through Plaid with read-only access, and it
reads alert emails for daily notes on what moved. The most valuable thing it
did was distrust its own data source. It pulled a full transaction export
from a budgeting app and found the app had been listing the same card
transactions twice under different card numbers. That inflated my spending
by a lot and invented "duplicate subscriptions" that didn't exist. It
also flagged a cluster of large charges at one merchant and told me to verify
them before paying the card.

When I asked, it also handled beneficiary paperwork across my investment
accounts, which is exactly the kind of task I'd been putting off for years.

### Home: a binder that keeps itself up to date

The Home bot built a Google Doc "Home Binder" and a Drive folder for the
house, and it keeps both current: mortgage details, insurance policies,
HOA documents with a plain-English summary of the rules, and warranty
records. It tracked down a builder warranty transfer I'd done years ago and
worked out exactly when each coverage tier had expired. It found that one
policy I thought I had cancelled was actually a separate flood policy that
was still my only flood coverage. It emailed my insurance agent for a
declarations page, then watched for the reply on a weekday schedule.

It also talked me out of things. It said no to a cleaning service whose
headline price turned out to be an auto-renewing membership with an early
cancellation fee. It said a home warranty didn't make sense for a newer
house. And when I asked whether to keep a property as a rental, it built a
multi-year model and laid out which inputs actually moved the answer.

### Medical: portals and paperwork, not diagnosis

The Medical bot reads appointment and portal notices from email, puts
appointments on my calendar with the prep notes, and booked a specialist
appointment through the office's online scheduler. Patient portals are where
it hits sign-in walls. It opens the portal on its own desktop and hands the
screen to me to sign in, then picks the work back up. It also drafted the
cover letter for an application form and told me which fields I still had
to fill in and sign myself.

### Tickets, Music, and Travel: the fun stuff

- **Tickets** relists tickets I can't use. It found the original order,
  uploaded the PDFs, set a price, and later dropped the price when I asked.
  For a festival wristband, it steered me to the festival's official resale
  partner and pointed out that the festival's terms might not honor tickets
  resold anywhere else. When a resale deadline was coming up, it set a check
  that runs a few times a day to look for the ticket email.
- **Music** read my SoundCloud likes (Spotify needed a sign-in on its
  desktop), summarized my taste, and ranked festivals and shows for a
  weekend I wanted to celebrate. When I said I didn't want to see one of
  the headliners, it went back and found better options.
- **Travel** booked a flight on my airline account. It covered the whole
  fare with an existing flight credit, got the window exit-row seat I asked
  for, and showed me the $0 total before booking. It also pulled hotel
  options near a festival and noted the free cancellation deadline.

### The router: cross-domain glue

The main bot handles the questions that span domains. I told it I had
cancelled two trips and asked it to verify. It sent a read-only subagent
through my email, calendar, and transactions, and came back with each
booking's status. One "cancellation" was actually a resale that I still had
to deliver, and one refund had come back as airline credit, not cash. It
also found the auto-created flight events still on my calendar and deleted
them when I asked, then searched again to confirm they were gone.

### Blog: this site

The Blog bot runs a weekday morning blog-ideas routine (paused right now)
that checks what's already published so it doesn't re-pitch a topic. It
drafts posts through cloud agents that open pull requests against this
site's repo. I review the PR, and the bot lets me preview locally before
anything goes live. This post went through the same loop.

## Where it broke, or nearly did

This is the section I'd want to read before trying any of this.

**Sign-in walls are the main bottleneck.** Bot protection on a budgeting app
blocked the Finance bot's sign-in outright. The fix was low-tech: I exported
a CSV myself and dropped it in. eBay stopped the Buy/Sell bot from viewing a
live auction listing more than once, so it fell back to reading eBay's
emails. Patient portals and streaming services needed me to sign in on the
bot's desktop. Plan for a human in the loop at login, every time.

**Platform rules beat good intentions.** The Bills bot tried to send my
reply to the phone carrier's support account in X Chat. X blocked it,
because encrypted chat only goes to accounts that follow you, and the
carrier's support account doesn't follow me. The bot told me it didn't go
out, gave me the text to paste myself, and explained why. A Facebook group
declined a resale post under its anti-scalping rule. The bot paused its
hourly buyer-reply routine, made a redacted receipt screenshot, and
resubmitted.

**Inferred is not known.** The Email bot drafted a message to an equipment
rental company and included a detail about my situation that it had inferred
but never actually confirmed. I approved the draft without noticing. Right
after it went out, the bot flagged its own mistake, said what it actually
knew versus what it had assumed, and offered to send a correction. I'm glad
it owned the mistake. The lesson is that I still have to read drafts,
not just skim them.

**Proactive can be stale.** The router sent me a helpful check-in tip for a
flight that I had already cancelled a week earlier. When I asked it to verify
the cancellations, it found the cancellation and told me to ignore its own
note. Proactive nudges are only as good as the last time the bot checked.

**Bots should push back on conflicting instructions, and mine did.** I told
the Tickets bot to drop a price the next day if the tickets hadn't sold. Later
I told the router to drop it right away. The Tickets bot noticed the
conflict, refused to guess, and asked the router to have me confirm one
option. That's the behavior you want from an operator.

## Path A vs Path B: one bot or a fleet?

**Path A, one general bot.** Less setup, one place to look, and memory isn't
split. It gets noisy fast, and every routine competes for the same context.
It's fine if you mostly ask one-off questions.

**Path B, a router plus specialists.** More bots to keep track of, and work
can fall between them. In exchange, each domain gets its own memory, its own
routines, and a clear owner. It's the right call if you want recurring work,
like bill checks, inbox briefs, and renewal reminders, to run without you.

I went with Path B and would again. I'd just add specialists more slowly.

## Takeaways

1. **Split by domain, not by task.** A bot that owns "home" builds up
   context that a bot asked one-off house questions never will.
2. **Keep approvals on anything you can't take back.** Sends, posts,
   purchases, and deletes all went through me. The one time I rubber-stamped
   a draft is the one time a wrong detail went out.
3. **Credentials go in the vault and secure forms, never in chat.** The
   best moments were when a bot set up a payment without ever seeing the
   bank numbers.
4. **Expect sign-in walls and design for the handoff.** Exports, email
   alerts, and "your turn to sign in" screens are the real integration
   layer for personal finance and healthcare.
5. **Make bots show their sources and their doubts.** The most valuable
   output wasn't a task completed. It was "your budgeting app is
   double-counting" and "this cancellation is actually a resale."
6. **Routines are cheap and chats are expensive.** Put recurring checks on
   a schedule and keep big one-off requests scoped.
7. **Prune the fleet.** Every half-finished bot is one more place for work
   to stall.

If you work in platform engineering, none of this will surprise you. It's
least privilege, separation of concerns, and change approval, applied to
the stuff that used to eat my weekends.
