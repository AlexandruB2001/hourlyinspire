import Foundation

/// 10x10 wildlife and treasure icons, drawn with the item palette so they sit
/// next to relics in the collection. Looked up through `ItemSprites.sprite`.
enum CreatureSprites {
    static let art: [String: String] = [
        // MARK: Wildlife
        "rabbit": """
            ..o..o....
            .owo.owo..
            .owo.owo..
            .owwwwwo..
            owowwowwo.
            owwwpwwwo.
            .owwwwwwo.
            .owwwwwwoo
            .owwwwwwwo
            ..oo..ooo.
            """,
        "bee": """
            ...o..o...
            ....oo....
            ..oWWoWWo.
            .oWWooWWo.
            .oyyoyyoyo
            oyyoyyoyyo
            .oyoyyoyo.
            ..oooooo..
            ..........
            ..........
            """,
        "otter": """
            ..........
            ..oo......
            .onnoo....
            onwnnno...
            onnnnnnoo.
            .onnnnnnno
            ..owwnnnno
            ..onnnnnno
            ...oo.oo.o
            ..........
            """,
        "kingfisher": """
            ..........
            ...ooo....
            ..ouuuo...
            .ouwouuoo.
            ooaaouuuuo
            ..oaaauuuo
            ...oaaaUo.
            ....ooUUo.
            .....o.oo.
            ..........
            """,
        "owl": """
            .o......o.
            .obooooob.
            .obbbbbbo.
            obwhobwhbo
            obwoobwobo
            .obbyybbo.
            .obnnnnbo.
            .obnbnbbo.
            ..obbbbo..
            ...oyoyo..
            """,
        "squirrel": """
            .....ooo..
            ....oaaao.
            ..o.oaAAao
            .oao..oaao
            .oaaao.oao
            oawoaaooao
            .oaaaaaao.
            ..oaaaao..
            ..oa.oao..
            ..oo..oo..
            """,
        "sheep": """
            ..........
            ..owowowo.
            .owwwwwwwo
            ooowwwwwwo
            oSoSwwwwwo
            .oSowwwwwo
            ..owwwwwo.
            ..oSo.oSo.
            ..oSo.oSo.
            ..........
            """,
        "frog": """
            ..........
            ..oo..oo..
            .owoooowo.
            .ogggggggo
            oggoooogg.
            ogGGGGGGgo
            .oggggggo.
            oggo..oggo
            oo......oo
            ..........
            """,
        "swan": """
            ..oo......
            .owwo.....
            .ooawo....
            ...owo....
            ...owo....
            ...owwwoo.
            ..owwwwwwo
            .owwwwwwwo
            ..okkkkko.
            ...ooooo..
            """,
        "cat": """
            .o.....o..
            .oo...oo..
            .ooooooo..
            oyoyyyoyo.
            oyyyPyyyo.
            .oyyyyyo..
            .oyyyyyyo.
            .oyyoyyyyo
            .oyoooyyoo
            .oo..oo...
            """,
        "wisp": """
            ....oo....
            ...occo...
            ..occwco..
            ..ocwwco..
            .occwwcco.
            .ocCccCco.
            ..occcco..
            ...oCCo...
            ..oc..co..
            ...o..o...
            """,
        "bat": """
            ..........
            o...oo...o
            oo.oSSo.oo
            oSooSSooSo
            oSSoSSoSSo
            .oSSoSoSo.
            ..oSSSSo..
            ...oSSo...
            ....oo....
            ..........
            """,
        "snow-fox": """
            .o....o...
            owo..owo..
            owwooowwo.
            owwwwwwwo.
            owowwowwo.
            .owwswwo..
            ..owwwwooo
            .owwwwwwwwo
            .owwowwoowo
            ..oo.oo.oo
            """,
        "turtle": """
            ..........
            ...oooo...
            ..oGgGgo..
            .oGgGgGgo.
            ooggggggoo
            ogoGGGGogo
            .ooooooooo
            .oLo..oLo.
            ..o....o..
            ..........
            """,
        "spirit": """
            ...oooo...
            ..oLLLLo..
            .oLwLLwLo.
            .oLoLLoLo.
            .oLLLLLLo.
            .ogLLLLgo.
            oLoLLLLoLo
            .ooLLLLoo.
            ..oLooLo..
            ...o..o...
            """,
        "goat": """
            o.o..o.o..
            .oo..oo...
            ..owwwo...
            .owowwoo..
            .owwwwwoo.
            ..owwwwwwo
            ..owwwwwwo
            ..oSwwwwSo
            ..oSo.oSo.
            ..oo..oo..
            """,
        "aurora-moth": """
            o........o
            .oo....oo.
            ocLo..oLco
            occLooLcco
            olcLooLclo
            .ollooollo
            ..oolloo..
            .olo..olo.
            .oo....oo.
            ..........
            """,
        "snow-monkey": """
            ..........
            ..oooooo..
            .owwwwwwo.
            owwppppwwo
            owpoppopwo
            owwpPPpwwo
            .owwppwwo.
            ..ocwwco..
            .occccccco
            ..ooooooo.
            """,
        "hedgehog": """
            ..........
            ...ooooo..
            ..oBoBoBo.
            .oBBBBBBBo
            onnoBBBBBo
            onowBBBBBo
            onnnnBBBBo
            .onnnnnnno
            ..oo...oo.
            ..........
            """,
        "panda": """
            .oo....oo.
            .oooooooo.
            .owwwwwwo.
            owoowwoowo
            owowwwwowo
            .owwoowwo.
            .oowwwwoo.
            oooowwoooo
            .oooooooo.
            ..oo..oo..
            """,
        "butterfly": """
            ..........
            oo..o..oo.
            omo.o.omo.
            ommoooommo
            omPmoomPmo
            .omooooomo
            .oPmoomPo.
            ..oo.o.oo.
            ..........
            ..........
            """,
        "deer": """
            o.o...o.o.
            .o.o.o.o..
            ..o.o.o...
            ...oooo...
            ..onwnno..
            ..onnnno..
            ...onnnooo
            ...onnnnno
            ...onwnwno
            ...on.on.o
            """,
        "lizard": """
            ..........
            ......ooo.
            .....oaaao
            o...oaoaao
            aoooaaaao.
            .oaaaaaao.
            ..oaAAaaao
            .oao..oa.o
            .oo...oo..
            ..........
            """,
        "firefly-sprite": """
            ..h....h..
            ...o..o...
            ..ohhhho..
            .ohwhhwho.
            .ohhhhhho.
            ..ohhhho..
            .hoyyyyoh.
            ..oyYYyo..
            ...oyyo...
            ....oo....
            """,
        "crab": """
            o........o
            ro......or
            oro....oro
            .orooooro.
            ..orwrwro.
            .orrrrrrro
            orrrrrrroo
            o.or..ro.o
            ..o....o..
            ..........
            """,
        "gull": """
            ..........
            ...ooo....
            ..owwwo...
            .owwowyyo.
            .owwwwoo..
            oSSwwwwwo.
            .oSSwwwwwo
            ..oSSwwwo.
            ...oyo.yo.
            ..........
            """,
        "whale": """
            ..........
            ...o.o....
            ..ouoo....
            .ouuuoooo.
            ouowuuuuuo
            ouuuuuuuuo
            owwwwwuuuo
            .owwwwwuo.
            ..oooooou.
            ........oo
            """,

        // MARK: Treasures
        "golden-acorn": """
            ...oooo...
            ..oYYYYo..
            .oYhyyyYo.
            .oooooooo.
            ..oyyhyo..
            ..oyyyyo..
            ..oyyyYo..
            ...oyYo...
            ....oo....
            ..........
            """,
        "pearl": """
            ..........
            ...oooo...
            ..owwwwo..
            .owhwwwko.
            .owwwwkko.
            .owwwkkko.
            ..okkkko..
            ...oooo...
            ..........
            ..........
            """,
        "ruby": """
            ..........
            ..oooooo..
            .orrrRrro.
            orrwrrRRro
            .orrrrRro.
            ..orrRRo..
            ...orRo...
            ....oo....
            ..........
            ..........
            """,
        "music-box": """
            ..........
            ...ooooo..
            ..ommmmmo.
            .ooooooooo
            .obbybbbbo
            .obbbbybbo
            .obybbbbbo
            .oooooooo.
            ..........
            ..........
            """,
        "old-map": """
            ..........
            .oooooooo.
            obnnnnnnbo
            onnrnnnnno
            onnnrrnnno
            onnnnnrnno
            onnnnnnrno
            obnnnnnnbo
            .oooooooo.
            ..........
            """,
        "star-shard": """
            ....o.....
            ...oho....
            ...oho....
            .oohhhoo..
            ohhhwhhho.
            .oohhhoo..
            ...oho....
            ...oho....
            ....o.....
            ..........
            """,
        "crown-jewel": """
            ..........
            .o..o..o..
            oyoyoyoyo.
            oyyyyyyyo.
            oycyryuyo.
            oyyyyyyyo.
            .ooooooo..
            ..........
            ..........
            ..........
            """,
        "amber": """
            ..........
            ...oooo...
            ..oaaaao..
            .oahaaaAo.
            .oaabaaAo.
            .oaaaaAAo.
            ..oAAAAo..
            ...oooo...
            ..........
            ..........
            """,
    ]
}
