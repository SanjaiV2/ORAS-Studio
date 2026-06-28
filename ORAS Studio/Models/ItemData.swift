import Foundation
import SwiftUI

// MARK: — Modèle d'objet ORAS (GARC a/0/1/1)
//
// Struct binaire little-endian, 36 octets par entrée (gen6 XY/ORAS) :
//   +0x00  price          u16   prix brut (× 10 = prix affiché en ₽)
//   +0x02  battleEffect   u8    effet en combat
//   +0x03  battlePower    u8    puissance de l'effet combat
//   +0x04  category       u8    catégorie interne (IA, ciblage)
//   +0x05  fieldEffect    u8    effet overworld (terrain)
//   +0x06  battleType     u8    type de ciblage en combat
//   +0x07  battleChance   u8    probabilité d'activation (%)
//   +0x08  battleUsage    u8    conditions d'usage combat
//   +0x09  battleParam    u8    paramètre combat supplémentaire
//   +0x0A  consumable     u8    1 = consommable en combat, 0 = réutilisable
//   +0x0B  holdEffect     u8    effet lorsque tenu par un Pokémon
//   +0x0C  holdParam      u8    paramètre de l'effet tenu
//   +0x0D  bagPocket      u8    poche du sac (0=Objets 1=Soins 2=Balls 3=CT/CS 4=Baies 5=Rares)
//   +0x0E  bagSort        u8    ordre de tri dans la poche
//   +0x0F  fieldSort      u8    ordre de tri pour usage terrain
//   +0x10  …              20 B  paramètres supplémentaires (préservés tels quels)

struct ItemData: Identifiable {
    let id: Int
    var name: String

    var price: UInt16
    var battleEffect: UInt8
    var battlePower: UInt8
    var category: UInt8
    var fieldEffect: UInt8
    var battleType: UInt8
    var battleChance: UInt8
    var battleUsage: UInt8
    var battleParam: UInt8
    var consumable: UInt8
    var holdEffect: UInt8
    var holdParam: UInt8
    var bagPocket: UInt8
    var bagSort: UInt8
    var fieldSort: UInt8

    var rawData: Data   // octets complets : modifiés sur les champs connus, rest préservé

    // MARK: — Catégorie affichée
    //
    // Dans ORAS (a/1/9/7), bagPocket=0 regroupe soins, baies ET CT/CS.
    // On utilise les plages d'IDs confirmées par analyse du GARC pour séparer les catégories.
    //   IDs  1–16  → Balls    (pocket=4)
    //   IDs 17–68  → Soins   (pocket=0)
    //   IDs 70–148 → Objets  (pocket=2)
    //   IDs 149–212→ Baies   (pocket=0)
    //   IDs 213–327→ Obj. rares / tenus (pocket=1)
    //   IDs 328+   → CT/CS   (pocket=0)

    var displayCategory: DisplayCategory {
        if bagPocket == 4                    { return .balls    }
        if (17...68).contains(id)            { return .medicine }
        if (149...212).contains(id)          { return .berries  }
        if id >= 328                         { return .tmhm     }
        if bagPocket == 1 || (213...327).contains(id) { return .keyItems }
        return .items
    }

    enum DisplayCategory: String, CaseIterable, Identifiable {
        case all      = "Tous"
        case medicine = "Soins"
        case items    = "Objets"
        case balls    = "Balls"
        case tmhm     = "CT / CS"
        case berries  = "Baies"
        case keyItems = "Objets rares"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:      "tray.2.fill"
            case .medicine: "cross.case.fill"
            case .items:    "bag.fill"
            case .balls:    "circle.fill"
            case .tmhm:     "opticaldisc.fill"
            case .berries:  "leaf.fill"
            case .keyItems: "key.fill"
            }
        }

        var color: Color {
            switch self {
            case .all:      .secondary
            case .medicine: .red
            case .items:    .blue
            case .balls:    .orange
            case .tmhm:     .purple
            case .berries:  .green
            case .keyItems: .yellow
            }
        }
    }

    static let strideSize = 36   // taille connue du struct gen6

    // MARK: — Parse

    static func parse(index: Int, data: Data, name: String = "") -> ItemData? {
        guard data.count >= 0x10 else { return nil }
        func u8(_ o: Int)  -> UInt8  { o < data.count ? data[o] : 0 }
        func u16(_ o: Int) -> UInt16 {
            guard o + 1 < data.count else { return 0 }
            return data.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
        }
        return ItemData(
            id:           index,
            name:         name.isEmpty ? String(format: "Objet %04d", index) : name,
            price:        u16(0x00),
            battleEffect: u8(0x02),
            battlePower:  u8(0x03),
            category:     u8(0x04),
            fieldEffect:  u8(0x05),
            battleType:   u8(0x06),
            battleChance: u8(0x07),
            battleUsage:  u8(0x08),
            battleParam:  u8(0x09),
            consumable:   u8(0x0A),
            holdEffect:   u8(0x0B),
            holdParam:    u8(0x0C),
            bagPocket:    u8(0x0D),
            bagSort:      u8(0x0E),
            fieldSort:    u8(0x0F),
            rawData:      data
        )
    }

    // MARK: — Encode (réécrit les champs connus, préserve le reste)

    func encode() -> Data {
        var out = rawData
        let minSize = 0x10
        if out.count < minSize { out += Data(repeating: 0, count: minSize - out.count) }
        out.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: price,        toByteOffset: 0x00, as: UInt16.self)
            ptr.storeBytes(of: battleEffect, toByteOffset: 0x02, as: UInt8.self)
            ptr.storeBytes(of: battlePower,  toByteOffset: 0x03, as: UInt8.self)
            ptr.storeBytes(of: category,     toByteOffset: 0x04, as: UInt8.self)
            ptr.storeBytes(of: fieldEffect,  toByteOffset: 0x05, as: UInt8.self)
            ptr.storeBytes(of: battleType,   toByteOffset: 0x06, as: UInt8.self)
            ptr.storeBytes(of: battleChance, toByteOffset: 0x07, as: UInt8.self)
            ptr.storeBytes(of: battleUsage,  toByteOffset: 0x08, as: UInt8.self)
            ptr.storeBytes(of: battleParam,  toByteOffset: 0x09, as: UInt8.self)
            ptr.storeBytes(of: consumable,   toByteOffset: 0x0A, as: UInt8.self)
            ptr.storeBytes(of: holdEffect,   toByteOffset: 0x0B, as: UInt8.self)
            ptr.storeBytes(of: holdParam,    toByteOffset: 0x0C, as: UInt8.self)
            ptr.storeBytes(of: bagPocket,    toByteOffset: 0x0D, as: UInt8.self)
            ptr.storeBytes(of: bagSort,      toByteOffset: 0x0E, as: UInt8.self)
            ptr.storeBytes(of: fieldSort,    toByteOffset: 0x0F, as: UInt8.self)
        }
        return out
    }

    // MARK: — Duplication pour ajout

    func duplicated(newID: Int) -> ItemData {
        ItemData(
            id: newID, name: String(format: "Objet %04d", newID),
            price: price, battleEffect: battleEffect, battlePower: battlePower,
            category: category, fieldEffect: fieldEffect, battleType: battleType,
            battleChance: battleChance, battleUsage: battleUsage, battleParam: battleParam,
            consumable: consumable, holdEffect: holdEffect, holdParam: holdParam,
            bagPocket: bagPocket, bagSort: 0, fieldSort: 0,
            rawData: Data(repeating: 0, count: max(rawData.count, ItemData.strideSize))
        )
    }
}
