# Core Concepts

Fundamental Skupper V2 concepts — the building blocks of application networks.

* [Skupper V2 Overview and Concept Model](overview-and-model.md) - Core concepts and architecture of Skupper V2 — sites, networks, services, and applications
* [Listener, Connector, and Routing Key Model](listener-connector-model.md) - How Skupper V2 exposes services using the Listener + Connector + Routing Key pattern
* [MultiKeyListener — Explicit Traffic Distribution](multi-key-listener.md) - How MultiKeyListener provides per-service weighted load balancing and priority failover across routing keys
* [Load Balancing and Failover Mechanisms](load-balancing-and-failover.md) - Two approaches to traffic distribution — link cost (implicit) vs MultiKeyListener (explicit)
* [Site Configuration — Edge Mode, Link Access, and HA](site-configuration.md) - How edge, linkAccess, and ha fields interact to define site topology and capabilities
* [AttachedConnector and AttachedConnectorBinding](attached-connectors.md) - Cross-namespace service exposure on Kubernetes without deploying a router in the workload namespace
