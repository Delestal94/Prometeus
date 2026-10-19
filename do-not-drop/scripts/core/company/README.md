# company

Persistent state of the company mode (expansion, D-0220): CompanyState (D-0202) and every number in company_tuning.gd, CompanyNet (host facts and snapshots; CompanyLayoutNet checks and applies its shed layout requests and events, D-0910; CompanyTableNet the shared packing tables' box_* requests and events, D-0715; CompanySnapshot packs the snapshot and checks what it carries), CompanySave (D-0206), DayCycle (D-0203), GameClock (D-0219, adapter of modules/day_clock) and CompanyLobbyMeta (D-2009, what Steam shows of the company through modules/net_session's NetSteamPresence).
Nothing here draws or plays sound: UI and audio listen to EventBus (docs/arquitectura.md §10).
