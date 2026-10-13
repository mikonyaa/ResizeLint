import SwiftSyntax

/// An offset index avoids repeatedly walking every preceding declaration in finding-heavy files.
struct SyntaxContext {
    private let tokens: [TokenSyntax]
    private let offsets: [Int]

    init(tree: SourceFileSyntax) {
        tokens = Array(tree.tokens(viewMode: .sourceAccurate))
        offsets = tokens.map { $0.positionAfterSkippingLeadingTrivia.utf8Offset }
    }

    func token(at offset: Int) -> TokenSyntax? {
        var lower = 0
        var upper = offsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if offsets[middle] <= offset { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        return tokens[lower - 1]
    }

    /// Only direct instance method/accessor bodies of known UIKit subclasses qualify.
    /// Closures, local functions, initializers, nested types and extensions need semantic review.
    func permitsTraitCollectionFix(at offset: Int) -> Bool {
        guard let token = token(at: offset) else { return false }
        var node = token.parent
        var instanceBody = false
        var owner: ClassDeclSyntax?
        while let ancestor = node {
            if ancestor.is(ClosureExprSyntax.self) || ancestor.is(InitializerDeclSyntax.self)
                || ancestor.is(DeinitializerDeclSyntax.self) || ancestor.is(SubscriptDeclSyntax.self) {
                return false
            }
            if let function = ancestor.as(FunctionDeclSyntax.self) {
                guard !instanceBody, !isTypeMember(function.modifiers),
                      function.parent?.is(MemberBlockItemSyntax.self) == true,
                      let body = function.body,
                      body.position.utf8Offset <= offset, offset < body.endPosition.utf8Offset else { return false }
                instanceBody = true
            }
            if let accessor = ancestor.as(AccessorDeclSyntax.self) {
                guard !instanceBody, let body = accessor.body,
                      body.position.utf8Offset <= offset, offset < body.endPosition.utf8Offset else { return false }
                instanceBody = true
            }
            if let variable = ancestor.as(VariableDeclSyntax.self),
               variable.parent?.is(MemberBlockItemSyntax.self) == true {
                guard !isTypeMember(variable.modifiers) else { return false }
                if !instanceBody {
                    instanceBody = variable.bindings.contains { binding in
                        guard let block = binding.accessorBlock,
                              block.position.utf8Offset <= offset, offset < block.endPosition.utf8Offset else { return false }
                        if case .getter = block.accessors { return true }
                        return false
                    }
                }
                guard instanceBody else { return false }
            }
            if let type = ancestor.as(ClassDeclSyntax.self) {
                guard owner == nil, instanceBody else { return false }
                owner = type
            } else if ancestor.is(StructDeclSyntax.self) || ancestor.is(EnumDeclSyntax.self)
                || ancestor.is(ActorDeclSyntax.self) || ancestor.is(ProtocolDeclSyntax.self)
                || ancestor.is(ExtensionDeclSyntax.self) {
                return false
            }
            node = ancestor.parent
        }
        guard let owner, let base = owner.inheritanceClause?.inheritedTypes.first?.type else { return false }
        let name = base.tokens(viewMode: .sourceAccurate).map(\.text).joined()
        let known = ["UIView", "UIViewController", "UITableViewCell", "UICollectionViewCell", "UIControl"]
        return known.contains(name) || known.contains { name == "UIKit.\($0)" }
    }

    func declarationTokens(at offset: Int) -> [String] {
        var node = token(at: offset)?.parent
        var declarations: [String] = []
        while let ancestor = node {
            if let declaration = ancestor.as(ClassDeclSyntax.self) {
                declarations.append("class:\(declaration.name.text)")
            } else if let declaration = ancestor.as(StructDeclSyntax.self) {
                declarations.append("struct:\(declaration.name.text)")
            } else if let declaration = ancestor.as(EnumDeclSyntax.self) {
                declarations.append("enum:\(declaration.name.text)")
            } else if let declaration = ancestor.as(ActorDeclSyntax.self) {
                declarations.append("actor:\(declaration.name.text)")
            } else if let declaration = ancestor.as(ProtocolDeclSyntax.self) {
                declarations.append("protocol:\(declaration.name.text)")
            } else if let declaration = ancestor.as(ExtensionDeclSyntax.self) {
                declarations.append("extension:\(text(declaration.extendedType)):\(declaration.genericWhereClause.map(text) ?? "")")
            } else if let declaration = ancestor.as(FunctionDeclSyntax.self) {
                declarations.append("func:\(text(declaration.modifiers)):\(declaration.name.text):\(declaration.genericParameterClause.map(text) ?? ""):\(text(declaration.signature)):\(declaration.genericWhereClause.map(text) ?? "")")
            } else if let declaration = ancestor.as(InitializerDeclSyntax.self) {
                declarations.append("init:\(text(declaration.signature))")
            } else if let declaration = ancestor.as(SubscriptDeclSyntax.self) {
                declarations.append("subscript:\(text(declaration.parameterClause)):\(text(declaration.returnClause))")
            } else if let declaration = ancestor.as(VariableDeclSyntax.self) {
                declarations.append("binding:" + declaration.bindings.map { text($0.pattern) }.joined(separator: ","))
            } else if let declaration = ancestor.as(AccessorDeclSyntax.self) {
                declarations.append("accessor:\(declaration.accessorSpecifier.text)")
            } else if ancestor.is(ClosureExprSyntax.self) {
                declarations.append("closure")
            }
            node = ancestor.parent
        }
        return declarations.reversed()
    }

    private func text(_ node: some SyntaxProtocol) -> String {
        node.tokens(viewMode: .sourceAccurate).map(\.text).joined(separator: " ")
    }

    private func isTypeMember(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
    }
}
