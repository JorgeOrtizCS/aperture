# Privacy-Preserving Content Sharing with Situational-Awareness Access Control

Capstone project (EGN4950C, Group 11) sponsored by Dr. Hari Kalva, FAU.

## Overview
Protects shared content (documents, images, messages) by enforcing viewer-defined
conditions (location, device, time, presence of other people, etc.) that must be
continuously satisfied while content is being viewed. If conditions are violated,
access is restricted.

## Structure
- `/mobile` — Flutter app (Android + iOS): sending/viewing UI, camera/GPS/biometric checks
- `/api` — .NET Framework 4.7.2 communication API: handles requests between mobile clients and backend
- `/db` — MySQL schema and migrations: user requirements, shared files, session data
- `/docs` — SRS, project summaries, meeting notes

## Team
- Colby Anger
- Rylee Texter
- Daniel Farafonov
- Jorge Ortiz
- Kyra Bernard

## Sponsor
Dr. Hari Kalva — hari.kalva@fau.edu
