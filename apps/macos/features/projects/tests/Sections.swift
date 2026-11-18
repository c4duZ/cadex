import AppKit
import Checks
import Icons
import UILooks
@testable import Projects

// The project page's sections (plan 34 C to E): the switch inside the page, the list and the
// rendered detail beside it.

@MainActor
func sectionsPage(_ section: ProjectSection) -> (ProjectPageDocument, NSWindow) {
    var actions = ProjectPageActions()
    actions.load = { show in show(ProjectPageState(name: "bkdg-center", place: "~/Cadu/Trabalho/bkdg/bkdg-center · dev/center · 34 memory pages · 29 sessions")) }
    actions.items = { section, query in
        guard section == .memory else {
            return [PageListItem(id: "s1", title: "Estado da memória do AI Memory", note: "fba. + BKDG · dev/center · 8 min", noteLogo: true),
                    PageListItem(id: "s2", title: "Avaliação de arquitetura do Space", note: "bhband · backend · 6 d", noteLogo: true)]
        }
        return [PageListItem(id: "r", title: "Nunca rodar migração sem backup do banco", note: "", tile: .pushPin, tint: DesignTokens.Color.stateReview, group: "Rules · what every agent gets"),
                PageListItem(id: "d", title: "Descrição de competência usa texto único com rótulos", note: "from \"Corrigir a descrição…\" · 2 h", tile: .checkCircle, tint: DesignTokens.Color.accentLink, group: "Decisions"),
                PageListItem(id: "g", title: "Ciclo guarda cópia das competências", note: "3 h", tile: .warning, tint: DesignTokens.Color.stateNeeds, group: "Cautions")]
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    actions.detail = { section, id in
        section == .memory
            ? PageDetail(chip: ("Decision", DesignTokens.Color.accentLink), title: "Descrição de competência usa texto único com rótulos",
                         meta: "from \"Corrigir a descrição das competências\" · bhband", metaLogo: true,
                         blocks: [.paragraph("A descrição de cada competência fica num campo de texto só, com rótulos."), .heading("Why"),
                                  .paragraph("Os níveis variam de 3 a 5 por competência."), .heading("Where"), .item("src/competencias/Descricao.tsx")],
                         buttons: [PageDetail.Button("Edit") {}, PageDetail.Button("Open the Session") {}, PageDetail.Button("Delete…", danger: true) {}])
            : PageDetail(title: "Estado da memória do AI Memory", meta: "fba. + BKDG · dev/center · today 14:34", metaLogo: true,
                         blocks: [.paragraph("Auditoria da memória ai-memory do bkdg-center."), .heading("What was done"), .item("Apagadas 6 páginas de outro projeto.")],
                         tags: ["ai-memory", "cadex"], relatedTitle: "What the memory kept", related: [.init(tile: .warning, tint: DesignTokens.Color.stateNeeds, text: "Páginas de sessão misturam projetos")],
                         buttons: [PageDetail.Button("Resume", primary: true) {}, PageDetail.Button("View the Page") {}])
    }
    let page = ProjectPageDocument(folder: "/tmp/bkdg-center", actions: actions)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = page.view
    page.show(section: section)
    page.view.layoutSubtreeIfNeeded()
    return (page, window)
}

@MainActor
func saveSectionsSnapshot(_ view: NSView, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
}

@MainActor
func sectionViews<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { sectionViews(type, in: $0) }
}

let sectionTests: [(name: String, body: Checks.Body)] = [
    ("Memory: the pages grouped, the first chosen and shown rendered beside the list; the search filters", { @MainActor in
        let (page, _) = sectionsPage(.memory)
        Checks.expect(page.section == .memory)
        Checks.expect(sectionViews(ListRow.self, in: page.view).count == 3, "three lines")
        Checks.expect(sectionViews(SearchField.self, in: page.view).count == 1, "the memory's search")
        saveSectionsSnapshot(page.view, "project-memory")
    }),
    ("Sessions: the list with the accounts and the chosen one's summary, what the memory kept and Resume", { @MainActor in
        let (page, _) = sectionsPage(.sessions)
        Checks.expect(sectionViews(ListRow.self, in: page.view).count == 2)
        Checks.expect(sectionViews(SearchField.self, in: page.view).isEmpty, "no search in Sessions")
        saveSectionsSnapshot(page.view, "project-sessions")
    }),
]
