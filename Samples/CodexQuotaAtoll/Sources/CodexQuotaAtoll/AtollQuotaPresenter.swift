import AtollExtensionKit
import CodexQuotaCore
import CoreGraphics
import Foundation

@MainActor
final class AtollQuotaPresenter {
    static let experienceID = "codex-dashboard"
    static let legacyActivityID = "codex-quota"
    static let actionActivityID = "codex-action-required"
    static let completionActivityID = "codex-task-completed"

    private let rpc = AtollRPCClient()
    private let preferences: CodexDashboardPreferences
    private var actionAlertKey: String?
    private var completionAlertKey: String?
    private var lastDescriptor: AtollNotchExperienceDescriptor?

    var isAtollInstalled: Bool { AtollClient.shared.isAtollInstalled }

    init(preferences: CodexDashboardPreferences) { self.preferences = preferences }

    func requestAuthorization() async throws -> Bool { try await rpc.requestAuthorization() }

    func removeLegacyActivity() async {
        try? await rpc.dismiss(activityID: Self.legacyActivityID)
        try? await rpc.dismiss(activityID: Self.actionActivityID)
        try? await rpc.dismiss(activityID: Self.completionActivityID)
    }

    func show(_ snapshot: CodexDashboardSnapshot) async throws {
        let descriptor = makeDescriptor(snapshot)
        if descriptor != lastDescriptor {
            do { try await rpc.update(descriptor) }
            catch { try await rpc.present(descriptor) }
            lastDescriptor = descriptor
        }
        await updateActionAlert(snapshot)
        await updateCompletionAlert(snapshot)
    }

    func close() async { await rpc.close() }

    private func makeDescriptor(_ snapshot: CodexDashboardSnapshot) -> AtollNotchExperienceDescriptor {
        let appearance = AtollWidgetAppearanceOptions(
            tintColor: preferences.accentTheme.atollColor,
            tintOpacity: 0.025,
            enableGlassHighlight: false,
            border: AtollWidgetBorderStyle(color: .white, opacity: 0, width: 0)
        )
        let webContent = AtollWidgetWebContentDescriptor(
            html: dashboardHTML(),
            preferredHeight: 236,
            isTransparent: true,
            allowLocalhostRequests: true,
            allowRemoteRequests: false
        )
        let tab = AtollNotchExperienceDescriptor.TabConfiguration(
            title: "Codex",
            iconSymbolName: "circle.hexagongrid.fill",
            badgeIcon: codexIcon(),
            preferredHeight: 352,
            appearance: appearance,
            sections: [],
            webContent: webContent,
            allowWebInteraction: true,
            contentLayout: .contentOnly,
            footnote: nil
        )
        return AtollNotchExperienceDescriptor(
            id: Self.experienceID,
            bundleIdentifier: AtollRPCClient.bundleIdentifier,
            priority: .normal,
            accentColor: color(for: snapshot.quota.lowestRemainingPercent ?? 100),
            metadata: metadata(for: snapshot),
            tab: tab,
            minimalistic: nil,
            durationHint: nil
        )
    }

    private func dashboardHTML() -> String {
        let theme = preferences.accentTheme
        let size = preferences.textSize
        return """
        <!doctype html><html data-accent="\(theme.rawValue)"><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
        :root{color-scheme:dark;--accent:\(theme.cssColor);--scale:\(size.cssScale);--ink:#f7f6fa;--muted:#a09ca8;--dim:#66616d;--line:rgba(255,255,255,.055);--panel:rgba(10,10,13,.96)}
        :root[data-accent=lavender]{--accent:#8f7dff}:root[data-accent=ocean]{--accent:#55b8ff}:root[data-accent=mint]{--accent:#5de6a0}:root[data-accent=rose]{--accent:#ff79a8}:root[data-accent=amber]{--accent:#ffb84d}
        *{box-sizing:border-box}html,body{margin:0;width:100%;height:236px;overflow:hidden;background:transparent;color:var(--ink);font-family:ui-monospace,"SFMono-Regular",Menlo,monospace;font-size:calc(10px*var(--scale));-webkit-font-smoothing:antialiased}button{font:inherit;color:inherit}.shell{height:236px;background:linear-gradient(180deg,rgba(15,14,18,.98),var(--panel));overflow:hidden}.top{height:31px;display:flex;align-items:center;gap:12px;padding:0 9px;border-bottom:1px solid var(--line)}
        .mark{width:14px;height:14px;display:grid;grid-template-columns:repeat(5,2px);grid-auto-rows:2px;gap:1px;transform:rotate(45deg);color:var(--accent)}.mark i{background:currentColor}.mark i:nth-child(even){opacity:.25}.quotas{display:flex;gap:13px;min-width:0}.quota{display:flex;align-items:baseline;gap:5px;white-space:nowrap}.quota label{font-size:calc(8px*var(--scale));font-weight:800;color:var(--muted)}.quota b{font-size:calc(11px*var(--scale));color:var(--accent);font-variant-numeric:tabular-nums}.quota time{font-size:calc(7px*var(--scale));color:var(--dim)}.fresh{margin-left:auto;font-size:calc(7px*var(--scale));color:var(--dim);white-space:nowrap}.fresh:before{content:"";display:inline-block;width:4px;height:4px;margin:0 5px 1px 0;background:#5de6a0;box-shadow:0 0 5px #5de6a0}.gear{width:18px;height:18px;border:0;background:transparent;padding:0;cursor:pointer;color:var(--dim);font-size:13px}.gear:hover{color:var(--accent)}
        .body{height:205px;overflow-y:auto;overscroll-behavior:contain;padding:5px 7px 10px;scrollbar-width:none}.body::-webkit-scrollbar{display:none}.loading,.empty{height:100%;display:grid;place-items:center;color:var(--dim);font-size:calc(9px*var(--scale));letter-spacing:.08em}.card{position:relative;padding:7px 7px 8px;background:rgba(255,255,255,.018);margin-bottom:5px}.card:before{content:"";position:absolute;left:0;top:7px;bottom:7px;width:2px;background:var(--state,var(--accent))}.head{display:flex;align-items:center;gap:7px;min-width:0}.state{width:16px;height:16px;display:grid;grid-template-columns:repeat(5,2px);grid-auto-rows:2px;gap:1px;place-content:center;color:var(--state)}.state i{width:2px;height:2px;background:currentColor;opacity:.08}.state i.on{opacity:1}.working .state i.on{animation:blink 1s steps(2,end) infinite}@keyframes blink{50%{opacity:.25}}.title{flex:1;min-width:0;font-size:calc(11px*var(--scale));font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.chip{font-size:calc(7px*var(--scale));padding:2px 4px;background:rgba(255,255,255,.05);color:var(--muted);white-space:nowrap}.age{font-size:calc(7px*var(--scale));color:var(--dim)}
        .activity{display:flex;gap:7px;margin:7px 0 3px 23px;color:var(--muted);line-height:1.35;font-size:calc(9px*var(--scale))}.activity .spark{color:var(--accent);flex:0 0 auto}.activity span:last-child{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}.tasks{margin:6px 0 0 23px;padding-top:5px;border-top:1px solid var(--line)}.tasks h4{margin:0 0 4px;font-size:calc(8px*var(--scale));color:var(--dim);letter-spacing:.06em}.task{display:flex;gap:6px;align-items:flex-start;min-height:16px;font-size:calc(8px*var(--scale));color:var(--muted)}.task i{font-style:normal;color:var(--accent)}.task.done{opacity:.55}.task.done span{text-decoration:line-through}.question{margin:7px 0 0 23px;padding:6px 7px;background:color-mix(in srgb,var(--accent) 10%,transparent)}.question b{display:block;font-size:calc(8px*var(--scale));color:var(--accent);margin-bottom:3px}.question p{margin:0 0 5px;font-size:calc(9px*var(--scale));line-height:1.35}.options{display:flex;flex-wrap:wrap;gap:4px}.option{border:0;background:rgba(255,255,255,.08);padding:4px 6px;cursor:pointer;font-size:calc(8px*var(--scale))}.option:hover{background:var(--accent);color:#0b0a0d}
        .complete{--state:#5de6a0;cursor:pointer}.complete .result{margin:5px 0 0 23px;color:var(--muted);font-size:calc(9px*var(--scale));white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.historyToggle{width:100%;height:26px;border:0;background:transparent;display:flex;align-items:center;gap:7px;padding:0 7px;color:var(--muted);cursor:pointer;font-size:calc(8px*var(--scale));border-bottom:1px solid var(--line)}.historyToggle:hover{color:var(--ink)}.historyToggle .arrow{color:var(--accent)}.historyToggle .count{margin-left:auto;color:var(--dim)}.history{display:none}.history.open{display:block}.session{width:100%;height:42px;border:0;background:transparent;display:flex;align-items:center;gap:7px;padding:3px 7px;text-align:left;cursor:pointer;border-bottom:1px solid var(--line)}.session:hover{background:rgba(255,255,255,.035)}.copy{flex:1;min-width:0}.copy b{display:block;font-size:calc(10px*var(--scale));white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.copy small{display:flex;gap:5px;margin-top:3px;font-size:calc(7px*var(--scale));color:var(--dim)}.copy em{font-style:normal;color:var(--status)}.speed{white-space:nowrap}.loader{height:18px;display:none;place-items:center;color:var(--accent);font-size:8px}.loader.on{display:grid}
        .palette{display:none;position:absolute;z-index:9;right:7px;top:27px;padding:7px;background:#151319;box-shadow:0 8px 24px #000;gap:6px;align-items:center}.palette.open{display:flex}.swatch{width:13px;height:13px;border:0;padding:0;cursor:pointer}.swatch.active{outline:1px solid #fff;outline-offset:2px}.font{height:18px;border:0;background:rgba(255,255,255,.07);padding:0 5px;cursor:pointer;font-size:9px}.font.active{background:var(--accent);color:#0b0a0d}.toast{display:none;position:absolute;left:50%;bottom:8px;transform:translateX(-50%);background:#242029;color:#fff;padding:5px 8px;font-size:8px;z-index:12}.toast.on{display:block}
        </style></head><body><main class="shell"><header class="top" onclick="openQuota()"><span class="mark"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span><div class="quotas" id="quotas"></div><span class="fresh" id="fresh">CACHE</span><button class="gear" onclick="togglePalette(event)" aria-label="Display settings">⚙</button></header><div class="palette" id="palette">\(paletteHTML(active: theme))<span style="width:1px;height:14px;background:var(--line)"></span>\(fontPaletteHTML(active: size))</div><section class="body" id="body"><div class="loading">CONNECTING TO CODEX…</div></section><div class="toast" id="toast">ANSWER COPIED · PASTE IN CODEX</div></main>
        <script>
        const bridge='http://127.0.0.1:\(CodexInteractionServer.port.rawValue)',body=document.getElementById('body');let shown=0,total=0,loading=false,historyOpen=false,lastMode='';
        const styles={preparing:['0111010001101011000101110','#64d2ff','PREPARING'],running:['1000011000111001100010000','#5de6a0','WORKING'],waitingForApproval:['0010000100001000000000100','#ffb84d','APPROVAL'],waitingForInput:['0111010001001100000000100','#be96ff','QUESTION'],reconnecting:['0111010000000011000101110','#64d2ff','RECONNECTING'],completed:['0000100010001001010001000','#5de6a0','COMPLETED'],idle:['0101001010010100101001010','#85828e','IDLE'],cancelled:['1000101010001000101010001','#85828e','CANCELLED'],timedOut:['1111110001010100010011111','#ffb84d','TIMED OUT'],failed:['1000101010001000101010001','#ff6961','FAILED'],disconnected:['1100000100001001000011000','#ff6961','OFFLINE']};
        function go(p){fetch(bridge+p,{mode:'no-cors'}).catch(()=>{})}function openQuota(){go('/open/quota')}function openThread(id){go('/open/thread?id='+encodeURIComponent(id))}function age(ts){let s=Math.max(0,Date.now()/1000-ts);if(s<60)return'now';if(s<3600)return Math.floor(s/60)+'m';if(s<86400)return Math.floor(s/3600)+'h';if(s<604800)return Math.floor(s/86400)+'d';return new Date(ts*1000).toLocaleDateString(undefined,{month:'short',day:'numeric'})}function reset(ts){let s=ts-Date.now()/1000;if(s>0&&s<86400){let h=Math.floor(s/3600),m=Math.floor((s%3600)/60);return'↻ '+(h?h+'h ':'')+m+'m'}return'↻ '+new Date(ts*1000).toLocaleDateString(undefined,{weekday:'short',hour:'2-digit',minute:'2-digit'})}function niceModel(x){return(x||'Codex').replace(/^gpt-/,'').replaceAll('-',' ')}
        function icon(state){let s=styles[state]||styles.idle,el=document.createElement('span');el.className='state';el.style.color=s[1];[...s[0]].forEach(x=>{let i=document.createElement('i');if(x==='1')i.className='on';el.append(i)});return el}function meta(t){let m=niceModel(t.model),e=t.effort?(' · '+t.effort):'',v=Number.isFinite(t.speed)?(' · '+t.speed.toFixed(1)+' tok/s'):'';return m+e+v}
        function quotaHTML(q){return q?'<span class="quota"><label>'+q.label.toUpperCase()+'</label><b>'+Math.round(q.remaining)+'%</b><time>'+reset(q.resetsAt)+'</time></span>':''}function renderTop(d){let q=quotaHTML(d.quota?.primary)+quotaHTML(d.quota?.secondary),el=document.getElementById('quotas');if(el.innerHTML!==q)el.innerHTML=q;let f='SYNC '+age(d.refreshedAt),fresh=document.getElementById('fresh');if(fresh.textContent!==f)fresh.textContent=f}
        function cardStructure(t){return JSON.stringify([t.id,t.state,t.title,t.model,t.effort,t.plan||[],t.question||null])}function activeCard(t){let s=styles[t.state]||styles.idle,c=document.createElement('article');c.className='card working';c.dataset.id=t.id;c.dataset.structure=cardStructure(t);c.style.setProperty('--state',s[1]);let h=document.createElement('div');h.className='head';h.append(icon(t.state));let title=document.createElement('span');title.className='title';title.textContent=t.title;let chip=document.createElement('span');chip.className='chip';chip.textContent=niceModel(t.model)+(t.effort?' · '+t.effort:'');let a=document.createElement('span');a.className='age';a.textContent=Number.isFinite(t.speed)?t.speed.toFixed(1)+' t/s':age(t.updatedAt);h.append(title,chip,a);h.onclick=()=>openThread(t.id);c.append(h);let act=document.createElement('div');act.className='activity';act.innerHTML='<span class="spark">✦</span><span></span>';act.lastChild.textContent=t.thinking||t.message||s[2];c.append(act);if(t.plan?.length){let tasks=document.createElement('div');tasks.className='tasks';tasks.innerHTML='<h4>TASKS · '+t.plan.filter(x=>x.status==='completed').length+'/'+t.plan.length+'</h4>';let active=t.plan.filter(x=>x.status==='in_progress'||x.status==='inProgress'),pending=t.plan.filter(x=>x.status!=='completed'&&!active.includes(x)),done=t.plan.filter(x=>x.status==='completed'),visible=t.plan.length<=4?t.plan:[...active,...pending,...done.slice(-3)].slice(0,4);visible.forEach(x=>{let r=document.createElement('div');r.className='task '+(x.status==='completed'?'done':'');r.innerHTML='<i>'+(x.status==='completed'?'✓':x.status==='in_progress'||x.status==='inProgress'?'▸':'·')+'</i><span></span>';r.lastChild.textContent=x.text;tasks.append(r)});c.append(tasks)}if(t.question){let q=document.createElement('div');q.className='question';let b=document.createElement('b');b.textContent=t.question.title||'QUESTION';let p=document.createElement('p');p.textContent=t.question.text;let opts=document.createElement('div');opts.className='options';(t.question.options||[]).forEach(o=>{let x=document.createElement('button');x.className='option';x.textContent=o.label;x.title='Copy answer and open this Codex task';x.onclick=e=>answer(e,t.id,o.label);opts.append(x)});q.append(b,p,opts);c.append(q)}return c}
        function completionCard(t){let c=document.createElement('article');c.className='card complete';c.onclick=()=>openThread(t.id);let h=document.createElement('div');h.className='head';h.append(icon('completed'));let title=document.createElement('span');title.className='title';title.textContent=t.title;let chip=document.createElement('span');chip.className='chip';chip.textContent=meta(t);h.append(title,chip);let r=document.createElement('div');r.className='result';r.textContent=t.message||'Task completed';c.append(h,r);return c}
        function session(t){let s=styles[t.state]||styles.idle,b=document.createElement('button');b.className='session';b.style.setProperty('--status',s[1]);b.onclick=()=>openThread(t.id);b.append(icon(t.state));let c=document.createElement('span');c.className='copy';let title=document.createElement('b');title.textContent=t.title;let small=document.createElement('small');let st=document.createElement('em');st.textContent=s[2];let mm=document.createElement('span');mm.textContent=niceModel(t.model)+(t.effort?' · '+t.effort:'');small.append(st,mm,document.createTextNode(' · '+age(t.updatedAt)));c.append(title,small);let speed=document.createElement('span');speed.className='age speed';speed.textContent=Number.isFinite(t.speed)?t.speed.toFixed(1)+' t/s':'— t/s';b.append(c,speed);return b}
        function historyShell(active,count){let f=document.createDocumentFragment();if(active){let t=document.createElement('button');t.className='historyToggle';t.innerHTML='<span class="arrow">'+(historyOpen?'▾':'▸')+'</span><span>HISTORY</span><span class="count">'+count+'</span>';t.onclick=()=>{historyOpen=!historyOpen;renderMode(window.dashboard)};f.append(t)}let h=document.createElement('div');h.id='history';h.className='history '+(!active||historyOpen?'open':'');let l=document.createElement('div');l.id='loader';l.className='loader';l.textContent='LOADING…';h.append(l);f.append(h);return f}
        async function loadMore(){let h=document.getElementById('history'),l=document.getElementById('loader');if(!h||loading||shown>=total)return;loading=true;l.classList.add('on');try{let r=await fetch(bridge+'/sessions?offset='+shown+'&limit=5'),p=await r.json();p.items.forEach(x=>h.insertBefore(session(x),l));shown+=p.items.length;total=p.total}catch(e){}finally{l.classList.remove('on');loading=false}}
        function renderMode(d){window.dashboard=d;let active=d.active?.length>0,mode=active?'active':'idle',scroll=body.scrollTop;body.innerHTML='';if(d.completion)body.append(completionCard(d.completion));(d.active||[]).forEach(t=>body.append(activeCard(t)));body.append(historyShell(active,d.threadCount));shown=0;total=d.threadCount;if(!active||historyOpen)loadMore();if(mode===lastMode)body.scrollTop=scroll;lastMode=mode}
        function layoutFingerprint(d){return JSON.stringify([(d.active||[]).map(cardStructure),d.completion?cardStructure(d.completion):null,d.threadCount])}function patchLive(d){let cards=[...body.querySelectorAll('.card.working')];if(cards.length!==(d.active||[]).length)return false;for(let i=0;i<cards.length;i++){let t=d.active[i],c=cards[i];if(c.dataset.id!==t.id||c.dataset.structure!==cardStructure(t))return false;let a=c.querySelector('.head .age'),v=Number.isFinite(t.speed)?t.speed.toFixed(1)+' t/s':age(t.updatedAt);if(a&&a.textContent!==v)a.textContent=v;let x=c.querySelector('.activity span:last-child'),s=styles[t.state]||styles.idle,m=t.thinking||t.message||s[2];if(x&&x.textContent!==m)x.textContent=m}return true}async function refresh(){try{let d=await(await fetch(bridge+'/dashboard',{cache:'no-store'})).json();renderTop(d);let fp=layoutFingerprint(d);if(fp!==window.fp||!patchLive(d)){window.fp=fp;renderMode(d)}else window.dashboard=d}catch(e){}}setInterval(refresh,1500);refresh();body.addEventListener('scroll',()=>{let h=document.getElementById('history');if(h&&h.classList.contains('open')&&body.scrollTop+body.clientHeight>=body.scrollHeight-10)loadMore()},{passive:true});body.addEventListener('wheel',e=>e.stopPropagation(),{passive:true});
        function answer(e,id,value){e.stopPropagation();go('/answer?thread='+encodeURIComponent(id)+'&value='+encodeURIComponent(value));let t=document.getElementById('toast');t.classList.add('on');setTimeout(()=>t.classList.remove('on'),1800)}function togglePalette(e){e.stopPropagation();document.getElementById('palette').classList.toggle('open')}function setAccent(e,n){e.stopPropagation();document.documentElement.dataset.accent=n;document.querySelectorAll('.swatch').forEach(x=>x.classList.toggle('active',x.dataset.name===n));go('/settings/accent?value='+n)}function setFont(e,n,v){e.stopPropagation();document.documentElement.style.setProperty('--scale',v);document.querySelectorAll('.font').forEach(x=>x.classList.toggle('active',x.dataset.name===n));go('/settings/font?value='+n)}
        </script></body></html>
        """
    }

    private func updateActionAlert(_ snapshot: CodexDashboardSnapshot) async {
        guard let thread = snapshot.threads.first(where: { snapshot.activity(for: $0).needsUserAction }) else {
            if actionAlertKey != nil { try? await rpc.dismiss(activityID: Self.actionActivityID); actionAlertKey = nil }
            return
        }
        let activity = snapshot.activity(for: thread)
        let question = snapshot.details(for: thread)?.question?.question
        let key = "\(thread.id):\(activity.rawValue):\(question ?? "")"
        guard key != actionAlertKey else { return }
        let isQuestion = activity == .waitingForInput
        let descriptor = AtollLiveActivityDescriptor(
            id: Self.actionActivityID,
            bundleIdentifier: AtollRPCClient.bundleIdentifier,
            priority: .high,
            title: isQuestion ? "Codex has a question" : "Codex needs approval",
            subtitle: trim(question ?? thread.displayName, length: 54),
            leadingIcon: .symbol(name: isQuestion ? "questionmark.bubble.fill" : "hand.raised.fill", size: 17),
            trailingContent: .icon(.symbol(name: "arrow.up.right", size: 13)),
            accentColor: isQuestion ? .purple : .orange,
            badgeIcon: codexIcon(),
            allowsMusicCoexistence: true,
            metadata: ["threadID": thread.id, "activity": activity.rawValue],
            sneakPeekConfig: AtollSneakPeekConfig(enabled: true, duration: 6, style: .standard, showOnUpdate: true),
            sneakPeekTitle: isQuestion ? "Codex has a question" : "Approval required",
            sneakPeekSubtitle: trim(question ?? thread.displayName, length: 54)
        )
        do { try await rpc.update(descriptor) } catch { try? await rpc.present(descriptor) }
        actionAlertKey = key
    }

    private func updateCompletionAlert(_ snapshot: CodexDashboardSnapshot) async {
        guard let thread = recentCompletion(in: snapshot), let details = snapshot.details(for: thread), let completed = details.turnCompletedAt else { return }
        let key = "\(thread.id):\(completed.timeIntervalSince1970)"
        guard key != completionAlertKey else { return }
        let descriptor = AtollLiveActivityDescriptor(
            id: Self.completionActivityID,
            bundleIdentifier: AtollRPCClient.bundleIdentifier,
            priority: .high,
            title: "Codex task completed",
            subtitle: trim(details.latestMessage ?? thread.displayName, length: 54),
            leadingIcon: .symbol(name: "checkmark.circle.fill", size: 17),
            trailingContent: .icon(.symbol(name: "arrow.up.right", size: 13)),
            accentColor: .green,
            badgeIcon: codexIcon(),
            allowsMusicCoexistence: true,
            metadata: ["threadID": thread.id, "activity": "completed"],
            sneakPeekConfig: AtollSneakPeekConfig(enabled: true, duration: 6, style: .standard, showOnUpdate: true),
            sneakPeekTitle: "Codex completed",
            sneakPeekSubtitle: trim(details.latestMessage ?? thread.displayName, length: 54)
        )
        do { try await rpc.update(descriptor) } catch { try? await rpc.present(descriptor) }
        completionAlertKey = key
    }

    private func recentCompletion(in snapshot: CodexDashboardSnapshot) -> CodexThreadSummary? {
        snapshot.threads.first { thread in
            guard snapshot.activity(for: thread) == .completed,
                  let date = snapshot.details(for: thread)?.turnCompletedAt else { return false }
            return Date().timeIntervalSince(date) < 30
        }
    }

    private func metadata(for snapshot: CodexDashboardSnapshot) -> [String: String] {
        var values = ["provider": "codex", "schemaVersion": "3"]
        if let thread = recentCompletion(in: snapshot), let date = snapshot.details(for: thread)?.turnCompletedAt {
            values["autoOpenEvent"] = "\(thread.id):\(Int64(date.timeIntervalSince1970))"
        }
        return values
    }

    private func paletteHTML(active: CodexAccentTheme) -> String {
        CodexAccentTheme.allCases.map { theme in
            let selected = theme == active ? " active" : ""
            return #"<button class="swatch\#(selected)" data-name="\#(theme.rawValue)" style="background:\#(theme.cssColor)" onclick="setAccent(event,'\#(theme.rawValue)')" aria-label="\#(theme.rawValue) accent"></button>"#
        }.joined()
    }

    private func fontPaletteHTML(active: CodexDashboardTextSize) -> String {
        CodexDashboardTextSize.allCases.map { size in
            let selected = size == active ? " active" : ""
            return #"<button class="font\#(selected)" data-name="\#(size.rawValue)" onclick="setFont(event,'\#(size.rawValue)',\#(size.cssScale))">\#(size.label)</button>"#
        }.joined()
    }

    private func codexIcon() -> AtollIconDescriptor {
        for path in [
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png",
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png",
        ] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return .image(data: data, size: CGSize(width: 32, height: 32), cornerRadius: 7)
            }
        }
        return .symbol(name: "circle.hexagongrid.fill", size: 24, weight: .semibold)
    }

    private func color(for remaining: Double) -> AtollColorDescriptor {
        switch remaining { case ...10: return .red; case ...25: return .orange; default: return preferences.accentTheme.atollColor }
    }

    private func trim(_ string: String, length: Int) -> String {
        string.count <= length ? string : String(string.prefix(length - 1)) + "…"
    }
}
