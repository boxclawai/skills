# Incident Postmortem Template & Guidelines

A comprehensive framework for conducting blameless postmortems, documenting incidents, and driving systematic improvement.

---

## Table of Contents

1. [Postmortem Document Template](#postmortem-document-template)
2. [Example Postmortem: Database Outage](#example-postmortem-database-outage)
3. [Blameless Postmortem Meeting Guide](#blameless-postmortem-meeting-guide)
4. [Follow-Up Tracking Process](#follow-up-tracking-process)

---

## Postmortem Document Template

```markdown
# Postmortem: [Incident Title]

| Field | Value |
|-------|-------|
| **Date of Incident** | YYYY-MM-DD |
| **Postmortem Date** | YYYY-MM-DD |
| **Severity** | SEV-1 / SEV-2 / SEV-3 / SEV-4 |
| **Duration** | X hours Y minutes |
| **Authors** | @name1, @name2 |
| **Reviewers** | @name3, @name4 |
| **Status** | Draft / In Review / Final |
| **Incident Commander** | @name |
| **Postmortem Meeting** | YYYY-MM-DD (link to recording) |

---

## Executive Summary

<!-- 2-3 sentence summary for leadership. Include: what happened, customer impact, and resolution. -->

On [date], [service/system] experienced [type of failure] for [duration],
affecting [number/percentage] of users. The root cause was [one-sentence root
cause]. The issue was resolved by [one-sentence resolution].

---

## Impact

### Customer Impact

| Metric | Value |
|--------|-------|
| Users affected | X (Y% of total) |
| Requests failed | X (Y% error rate) |
| Revenue impact | $X estimated |
| SLA violation | Yes/No (remaining budget: X%) |
| Support tickets filed | X |
| Public-facing status page | Updated at HH:MM UTC |

### Internal Impact

- Engineering hours spent on incident: X person-hours
- Delayed releases or projects: [list]
- Downstream service impact: [list affected services]

### Severity Justification

<!-- Explain why this incident received its severity rating. -->

This incident was classified as SEV-[N] because:
- [Criterion 1 from severity matrix]
- [Criterion 2 from severity matrix]

---

## Timeline

All times in UTC.

| Time | Event |
|------|-------|
| HH:MM | [Triggering event or deployment] |
| HH:MM | First monitoring alert fires: [alert name] |
| HH:MM | On-call engineer [name] acknowledges alert |
| HH:MM | Incident declared, Slack channel #inc-XXXX created |
| HH:MM | Incident Commander [name] assumes coordination |
| HH:MM | [Investigation step: what was checked and what was found] |
| HH:MM | [Investigation step: what was checked and what was found] |
| HH:MM | Root cause identified: [brief description] |
| HH:MM | Mitigation applied: [action taken] |
| HH:MM | Service recovery confirmed via [metric/dashboard] |
| HH:MM | Incident resolved, all-clear communicated |
| HH:MM | Follow-up monitoring period begins |

### Detection

- **How was the incident detected?** Monitoring alert / Customer report / Manual discovery
- **Detection latency:** X minutes from onset to first alert
- **Could we have detected this sooner?** Yes/No -- [explanation]

---

## Root Cause Analysis

### Summary

<!-- One paragraph explaining the technical root cause. -->

### 5 Whys Analysis

1. **Why did [the observable symptom] occur?**
   Because [immediate technical cause].

2. **Why did [immediate technical cause] happen?**
   Because [deeper cause].

3. **Why did [deeper cause] happen?**
   Because [systemic cause].

4. **Why did [systemic cause] exist?**
   Because [process/organizational cause].

5. **Why did [process/organizational cause] persist?**
   Because [fundamental root cause].

### Contributing Factors

<!-- List all factors that contributed to the incident, even if they are not the primary root cause. -->

- **Factor 1:** [Description and how it contributed]
- **Factor 2:** [Description and how it contributed]
- **Factor 3:** [Description and how it contributed]

### Trigger vs. Root Cause

- **Trigger:** [The specific event that initiated the incident, e.g., a deployment, config change, traffic spike]
- **Root Cause:** [The underlying condition that allowed the trigger to cause an outage]

---

## What Went Well

<!-- Recognize things that worked correctly during the incident. This is important for a blameless culture. -->

- [ ] Monitoring detected the issue within X minutes
- [ ] Incident response process was followed correctly
- [ ] Communication to stakeholders was timely and clear
- [ ] Rollback procedure worked as expected
- [ ] Team collaboration was effective
- [ ] [Specific technical safeguard that limited blast radius]
- [ ] [Specific process that accelerated resolution]

---

## What Went Wrong

<!-- Be specific and factual. Focus on systems, processes, and tooling -- not individuals. -->

- [ ] [Monitoring gap: specific metric/alert that was missing]
- [ ] [Runbook was outdated or missing for this scenario]
- [ ] [Deployment pipeline lacked specific safety check]
- [ ] [Communication delay: stakeholders not informed for X minutes]
- [ ] [Recovery was slowed by: specific tooling/access issue]
- [ ] [Testing gap: scenario not covered by existing tests]

---

## Where We Got Lucky

<!-- Identify factors that limited impact but were not by design. These represent hidden risks. -->

- [e.g., Low traffic period meant fewer users were affected]
- [e.g., A team member happened to be online who had specific knowledge]
- [e.g., The failure mode caused a graceful degradation by coincidence]

---

## Action Items

<!-- Every action item MUST have an owner, a deadline, a priority, and a tracking ticket. -->

### Prevent Recurrence (P0 -- Complete within 1 week)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 1 | [Specific fix to prevent this exact failure] | @name | YYYY-MM-DD | PROJ-XXX | Open |
| 2 | [Add missing test/validation] | @name | YYYY-MM-DD | PROJ-XXX | Open |

### Improve Detection (P1 -- Complete within 2 weeks)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 3 | [Add/improve monitoring alert] | @name | YYYY-MM-DD | PROJ-XXX | Open |
| 4 | [Improve logging for faster diagnosis] | @name | YYYY-MM-DD | PROJ-XXX | Open |

### Improve Response (P1 -- Complete within 2 weeks)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 5 | [Update/create runbook] | @name | YYYY-MM-DD | PROJ-XXX | Open |
| 6 | [Improve incident tooling] | @name | YYYY-MM-DD | PROJ-XXX | Open |

### Systemic Improvements (P2 -- Complete within 1 month)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 7 | [Architecture/design change to prevent class of failures] | @name | YYYY-MM-DD | PROJ-XXX | Open |
| 8 | [Process improvement] | @name | YYYY-MM-DD | PROJ-XXX | Open |

---

## Appendix

### Related Incidents

- [Link to similar past incidents]
- [Link to incidents in the same system]

### Supporting Data

- [Link to relevant dashboards during incident window]
- [Link to relevant log queries]
- [Link to deployment diff or config change]

### Glossary

- **Term:** Definition relevant to this incident
```

---

## Example Postmortem: Database Outage

```markdown
# Postmortem: Primary Database Connection Pool Exhaustion

| Field | Value |
|-------|-------|
| **Date of Incident** | 2025-11-15 |
| **Postmortem Date** | 2025-11-18 |
| **Severity** | SEV-1 |
| **Duration** | 2 hours 17 minutes |
| **Authors** | @sarah.chen, @marcus.johnson |
| **Reviewers** | @lisa.park, @david.kim |
| **Status** | Final |
| **Incident Commander** | @lisa.park |
| **Postmortem Meeting** | 2025-11-19 (recording link) |

---

## Executive Summary

On November 15, 2025, the primary PostgreSQL database experienced connection
pool exhaustion from 14:23 to 16:40 UTC, causing intermittent 500 errors
for approximately 34% of API requests affecting 12,400 users. The root cause
was a long-running analytics query that acquired row-level locks on the
orders table, causing application connection pool starvation as queries
queued behind the lock. The issue was resolved by terminating the offending
query and implementing a statement timeout.

---

## Impact

### Customer Impact

| Metric | Value |
|--------|-------|
| Users affected | 12,400 (34% of active users) |
| Requests failed | 847,000 (31% error rate at peak) |
| Revenue impact | $23,000 estimated (failed checkouts) |
| SLA violation | Yes (99.9% target, actual 98.7% for the day) |
| Support tickets filed | 187 |
| Public-facing status page | Updated at 14:45 UTC |

### Internal Impact

- Engineering hours spent: 14 person-hours (incident) + 20 person-hours (postmortem + fixes)
- Delayed Q4 release by 2 days
- Customer Success team handled 187 tickets over 3 days

---

## Timeline

All times in UTC.

| Time | Event |
|------|-------|
| 13:50 | Data analyst runs ad-hoc query against production orders table via read replica that was misconfigured to point to primary |
| 14:15 | Query acquires row-level locks on 2.3M rows in the orders table |
| 14:23 | Application connection pool hits maximum (100 connections), new requests begin queuing |
| 14:25 | Datadog alert fires: "API error rate > 5%" -- PagerDuty pages on-call @marcus.johnson |
| 14:28 | Marcus acknowledges alert, begins investigation |
| 14:32 | Marcus observes elevated 500 errors on /api/orders/* endpoints specifically |
| 14:35 | Marcus checks database dashboard, sees 100/100 connections in use, 340 queries queued |
| 14:38 | Incident declared as SEV-1, #inc-2025-1115-db created in Slack |
| 14:40 | @lisa.park assumes Incident Commander role |
| 14:45 | Status page updated: "Investigating elevated error rates" |
| 14:52 | Marcus identifies long-running query (PID 28471) holding locks for 62 minutes |
| 14:55 | Marcus attempts to cancel query via pg_cancel_backend -- query does not respond |
| 14:58 | Marcus terminates query via pg_terminate_backend -- connection killed |
| 15:05 | Connection pool begins draining, error rate drops to 12% |
| 15:20 | Error rate normalizes to baseline (<0.1%) |
| 15:25 | Status page updated: "Monitoring -- issue appears resolved" |
| 16:00 | Marcus and Sarah implement emergency statement_timeout of 300s |
| 16:30 | Statement timeout deployed, verified in production |
| 16:40 | Incident resolved, all-clear communicated |
| 16:40 | 24-hour monitoring window begins |

### Detection

- **How detected:** Automated monitoring (Datadog error rate alert)
- **Detection latency:** 2 minutes from connection pool saturation to alert
- **Could we have detected sooner?** Yes. A connection pool utilization alert at 80% threshold would have fired ~8 minutes earlier.

---

## Root Cause Analysis

### Summary

A data analyst ran an unoptimized analytical query directly against the
primary production database. The analyst's connection string was configured
to use the read replica, but the replica's connection configuration had been
inadvertently changed during a maintenance window two weeks prior to point
back to the primary. The query performed a full table scan on the 2.3M-row
orders table with `FOR UPDATE` semantics (due to the ORM's default
configuration for the analyst toolkit), acquiring row-level locks. This
blocked all application writes and most reads on the orders table, causing
connection pool exhaustion as application threads waited for locks.

### 5 Whys Analysis

1. **Why did API requests fail?**
   Because the application connection pool was exhausted (100/100 connections in use).

2. **Why was the connection pool exhausted?**
   Because application queries were blocked waiting for row-level locks on the orders table, and connections were not being returned to the pool.

3. **Why were row-level locks held on the orders table?**
   Because a long-running analytics query had acquired FOR UPDATE locks on 2.3M rows and was still executing after 60+ minutes.

4. **Why was an analytics query running against the primary database with write locks?**
   Because (a) the read replica connection string had been misconfigured to point to the primary during a maintenance window 2 weeks ago, and (b) the analyst toolkit ORM defaults to FOR UPDATE mode.

5. **Why was the misconfigured replica connection not detected for 2 weeks?**
   Because there is no automated validation that replica connections actually point to replica instances, and read-only traffic to the primary does not generate distinguishable errors.

### Contributing Factors

- **No statement timeout:** The database had no global statement_timeout configured, allowing queries to run indefinitely.
- **No connection pool monitoring:** No alert on connection pool utilization approaching capacity.
- **Analyst toolkit defaults:** The ORM used by the data team defaults to FOR UPDATE locking, which is inappropriate for read-only analytics.
- **Shared database access:** Analysts and applications share the same database without resource isolation or query governance.

---

## What Went Well

- Monitoring detected the elevated error rate within 2 minutes
- On-call engineer diagnosed the issue within 27 minutes
- Incident Commander was engaged within 15 minutes
- Status page was updated within 22 minutes of first alert
- The team had psql access to production and was able to terminate the query
- Communication in the incident channel was clear and structured

---

## What Went Wrong

- No statement timeout was configured on the production database
- No connection pool utilization alert existed (only error rate)
- Read replica misconfiguration went undetected for 2 weeks
- pg_cancel_backend failed, requiring the more disruptive pg_terminate_backend
- The analyst toolkit defaults to FOR UPDATE locks on all queries
- No query governance for direct database access
- Initial rollback attempt (restarting the application) did not help because the lock was still held

---

## Where We Got Lucky

- The analyst ran the query during afternoon hours (US), not during peak morning traffic -- impact would have been 3x worse during peak
- The on-call engineer (Marcus) had deep PostgreSQL expertise and quickly identified the lock issue -- a less experienced engineer might have spent more time on application-level debugging
- The query eventually would have completed on its own (estimated 4+ hours), but we were able to terminate it manually

---

## Action Items

### Prevent Recurrence (P0 -- Complete by 2025-11-22)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 1 | Set statement_timeout = 300s on production database | @marcus.johnson | 2025-11-16 | DB-1201 | Done |
| 2 | Fix read replica connection string, verify it points to actual replica | @sarah.chen | 2025-11-17 | DB-1202 | Done |
| 3 | Configure analyst toolkit ORM to use read-only mode by default | @sarah.chen | 2025-11-22 | DATA-445 | In Progress |

### Improve Detection (P1 -- Complete by 2025-11-29)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 4 | Add connection pool utilization alert at 80% threshold | @marcus.johnson | 2025-11-20 | MON-892 | Done |
| 5 | Add alert for queries running longer than 60 seconds | @marcus.johnson | 2025-11-22 | MON-893 | In Progress |
| 6 | Add automated validation that replica connections resolve to replica instances | @sarah.chen | 2025-11-29 | DB-1203 | Open |

### Improve Response (P1 -- Complete by 2025-11-29)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 7 | Create runbook for "database connection pool exhaustion" | @marcus.johnson | 2025-11-25 | RUN-341 | Open |
| 8 | Add pg_stat_activity dashboard to incident response quick links | @marcus.johnson | 2025-11-22 | MON-894 | Open |

### Systemic Improvements (P2 -- Complete by 2025-12-15)

| # | Action Item | Owner | Deadline | Ticket | Status |
|---|-------------|-------|----------|--------|--------|
| 9 | Implement PgBouncer with per-user connection limits to isolate analyst vs. application traffic | @sarah.chen | 2025-12-08 | DB-1204 | Open |
| 10 | Evaluate migration of analyst workloads to a dedicated analytics database (read replica with separate connection pool) | @lisa.park | 2025-12-15 | ARCH-567 | Open |
| 11 | Implement query allowlist/governance for direct database access | @david.kim | 2025-12-15 | SEC-234 | Open |
```

---

## Blameless Postmortem Meeting Guide

### Core Principles

1. **Blameless does not mean accountable-less.** We hold systems, processes, and tooling accountable -- not individuals. People made the best decisions they could with the information they had at the time.

2. **Assume good intent.** Everyone involved was trying to do their job well. The question is: "What about our systems allowed this to happen?" not "Who made a mistake?"

3. **Focus on learning.** The goal is to make the system more resilient, not to assign blame.

4. **Discomfort is expected.** Honest discussion about failures is uncomfortable. That discomfort is a sign the conversation is productive.

### Before the Meeting

**Facilitator Responsibilities (typically the Incident Commander or Engineering Manager):**

| Task | Timeline |
|------|----------|
| Draft the postmortem document with timeline and known facts | Within 48 hours of incident resolution |
| Circulate draft to all participants for async review | At least 24 hours before meeting |
| Schedule 60-minute meeting with all involved parties | Within 5 business days of incident |
| Prepare the room: ensure psychological safety ground rules are visible | Day of meeting |
| Identify a dedicated note-taker (not the facilitator) | Before meeting |

**Participant Responsibilities:**

- Review the draft postmortem document before the meeting
- Add corrections or additional context to the timeline
- Come prepared to discuss contributing factors honestly
- Think about systemic improvements, not individual mistakes

### Meeting Agenda (60 minutes)

| Time | Section | Duration | Notes |
|------|---------|----------|-------|
| 0:00 | **Opening & Ground Rules** | 5 min | Facilitator reads ground rules, sets expectations |
| 0:05 | **Timeline Review** | 15 min | Walk through the timeline. Correct inaccuracies. Fill gaps. |
| 0:20 | **Root Cause Discussion** | 15 min | Work through the 5 Whys together. Challenge assumptions. |
| 0:35 | **What Went Well / What Went Wrong** | 10 min | Identify bright spots and systemic issues |
| 0:45 | **Action Items** | 10 min | Assign owners, set deadlines, prioritize |
| 0:55 | **Closing** | 5 min | Summarize decisions, confirm follow-up process |

### Ground Rules (Read Aloud at Start)

```
1. We are here to learn, not to blame.
2. Everyone involved acted with the best information available at the time.
3. "Human error" is never a root cause. We ask: "What about our systems
   made this error possible or likely?"
4. Speak from your own perspective: "I observed..." not "You should have..."
5. All questions are welcome. There are no stupid questions.
6. Disagree with ideas, not people.
7. What is shared here stays here. The published postmortem will be factual
   and blameless.
8. It is okay to say "I don't know" or "I was confused at that point."
```

### Facilitator Techniques

**For drawing out information:**
- "Walk us through what you were seeing on your screen at that point."
- "What information would have helped you make a different decision?"
- "At time T, what did you believe was happening? What turned out to be different?"
- "Were there any moments where you felt uncertain about what to do next?"

**For redirecting blame:**
- If someone says "Person X should have...": Redirect with "Let's think about what our systems could have done to prevent that situation from arising."
- If someone is self-blaming: "It sounds like our process put you in a position where that outcome was likely. Let's focus on how we can change the process."

**For keeping discussion productive:**
- "Let's add that to the action items and discuss solutions offline."
- "I want to make sure we hear from everyone. [Name], what was your experience during this?"
- "We have 10 minutes left for this section. Let's focus on the highest-impact items."

**For handling defensiveness:**
- Acknowledge the discomfort: "I know this is uncomfortable to discuss. That's normal and it means we're having an honest conversation."
- Reframe to systems: "Rather than focusing on what happened, let's discuss what our systems could have done differently."

### Anti-Patterns to Avoid

| Anti-Pattern | What It Looks Like | What To Do Instead |
|-------------|--------------------|--------------------|
| **Blame assignment** | "If only [person] had checked the config..." | "What process could verify configs automatically?" |
| **Counterfactual reasoning** | "If we had done X, this would never have happened" | "What signals could we monitor to detect this class of issue?" |
| **Minimizing** | "It wasn't that bad, only 5% of users were affected" | "5% of users is 12,000 people. Let's ensure this doesn't recur." |
| **Hero narrative** | "Thankfully [person] was there to save the day" | "How can we ensure anyone on-call could resolve this?" |
| **Premature solution-jumping** | "We should just add more database replicas" | "Let's first understand all contributing factors before proposing solutions." |
| **Scope creep** | Discussion expands to every known problem | "Let's capture that as a separate item and stay focused on this incident." |

---

## Follow-Up Tracking Process

### Action Item Lifecycle

```
Created --> Assigned --> In Progress --> In Review --> Completed --> Verified
                  \                                         |
                   \--> Deferred (with justification) ------/
```

### Review Cadence

| Interval | Activity | Owner |
|----------|----------|-------|
| **Weekly** | Review open P0/P1 action items in team standup | Engineering Manager |
| **Bi-weekly** | Review all open postmortem action items | Tech Lead |
| **Monthly** | Postmortem action item completion report to leadership | Engineering Manager |
| **Quarterly** | Postmortem trends analysis and systemic review | VP Engineering |

### Completion Criteria

An action item is considered complete when:

1. The code/configuration/process change has been deployed to production
2. The change has been verified to work as intended (not just merged)
3. Related documentation (runbooks, alerts, dashboards) has been updated
4. The ticket has been updated with evidence of completion

### Escalation Process

| Condition | Action |
|-----------|--------|
| P0 action item not started within 3 days | Escalate to Engineering Manager |
| P1 action item not started within 1 week | Escalate to Engineering Manager |
| Any action item missed deadline by > 3 days | Escalate to Tech Lead |
| Action item repeatedly deferred (2+ times) | Escalate to VP Engineering |

### Metrics to Track

Track these metrics across all postmortems to identify systemic trends:

| Metric | Target | Description |
|--------|--------|-------------|
| **Mean Time to Detect (MTTD)** | < 5 min | Time from incident onset to first alert |
| **Mean Time to Respond (MTTR)** | < 15 min | Time from alert to first human action |
| **Mean Time to Resolve** | Varies by SEV | Time from onset to full resolution |
| **Action Item Completion Rate** | > 90% | % of action items completed by deadline |
| **Postmortem Completion Rate** | 100% for SEV-1/2 | % of qualifying incidents with completed postmortems |
| **Repeat Incidents** | 0 | Incidents with same root cause as a previous incident |
| **Detection Method** | > 80% automated | % of incidents detected by monitoring vs. humans |

### Quarterly Trends Review Template

```markdown
## Postmortem Trends: Q[N] YYYY

### Summary Statistics
- Total incidents: X (SEV-1: A, SEV-2: B, SEV-3: C)
- Postmortems completed: X/Y (Z%)
- Action items created: X
- Action items completed on time: X/Y (Z%)

### Top Contributing Factor Categories
1. [Category]: X incidents (e.g., configuration errors)
2. [Category]: X incidents (e.g., missing monitoring)
3. [Category]: X incidents (e.g., dependency failures)

### Systemic Issues Identified
- [Issue that appeared in multiple postmortems]
- [Issue that appeared in multiple postmortems]

### Improvements Since Last Quarter
- [Specific improvement and its measurable impact]
- [Specific improvement and its measurable impact]

### Recommendations
- [Recommendation with business justification]
- [Recommendation with business justification]
```

### Severity Definitions

Use these definitions consistently across all postmortems:

| Severity | Definition | Postmortem Required | Timeline |
|----------|------------|-------------------|----------|
| **SEV-1** | Complete service outage or data loss affecting >25% of users | Yes (mandatory) | Within 3 business days |
| **SEV-2** | Major feature degradation affecting >10% of users, or any data integrity issue | Yes (mandatory) | Within 5 business days |
| **SEV-3** | Minor feature degradation affecting <10% of users, with workaround available | Recommended | Within 10 business days |
| **SEV-4** | Cosmetic issue or internal tooling failure with no user impact | Optional | As needed |
