local maps_formula_d
local maps_formula_de
local maps_custom
local mapTileGUID
local memoryBagSetupGUID
local memoryBagModMenuGUID

function onLoad(save_state)


    mapTileGUID = "ebde54"
    memoryBagSetupGUID = "0fde3b"
    memoryBagSetup = getObjectFromGUID(memoryBagSetupGUID)

    memoryBagModMenuGUID = "a57988"
    memoryBagModMenu = getObjectFromGUID(memoryBagModMenuGUID)

    maps_formula_d = {}
    maps_formula_d["Formula D: Monaco"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014232538/CC3911BF378E3DA31959B56901F60A14B456A1FF/"
    maps_formula_d["Formula D: Race City"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014233913/FDDA7626CA3F65CFB21601577F05C7E2364E62C1/"
    maps_formula_d["Formula D: Race City (Alt)"] = "https://steamusercontent-a.akamaihd.net/ugc/1014943781014235128/29D90BF72EF0F8797A30F5F2E39A5C725C1E711F/"
    maps_formula_d["Formula D: Sebring"] =         "https://steamusercontent-a.akamaihd.net/ugc/1014943781014237078/FDC094E0C1FF2870B60554A293DC15414BAFCF8F/"
    maps_formula_d["Formula D: Chicago"] =         "https://steamusercontent-a.akamaihd.net/ugc/1014943781014238203/908BBF22412D68A0CED43D6DAB6F93E73DE97239/"
    maps_formula_d["Formula D: Hockenheim"] =      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014239414/7980D8F0867FB1439C017653462FDD9242670F9B/"
    maps_formula_d["Formula D: Valencia"] =        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014240406/80F9F33ECB931991D025DB32A0D97DC61037450A/"
    maps_formula_d["Formula D: Docks"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014241911/4D5CB22E13E9C014858B43596DFE2A628DF8CC2B/"
    maps_formula_d["Formula D: Docks (Alt)"] =     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014243040/E383145AB9B72D56A3A480E10ECEC452C07709C8/"
    maps_formula_d["Formula D: Singapore"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014244002/1806D1182356A335F1EC9A740C4448939B37725E/"
	    maps_formula_d["Formula D: Baltimore"] = 	      "https://steamusercontent-a.akamaihd.net/ugc/1014943920262829636/67BB74395A04A9B0596033157461FC9C77BB55D9/"
    	maps_formula_d["Formula D: Buddh"] = 		          "https://steamusercontent-a.akamaihd.net/ugc/1014943920262832180/147A3A167C17284615698923BC9B37E7897BFC6B/"
    	maps_formula_d["Formula D: New Jersey"] =   	   "https://steamusercontent-a.akamaihd.net/ugc/1014943920262832692/A579B7C010410CC2ACAE93FFED9027C1B6159809/"
    	maps_formula_d["Formula D: Sotchi"] = 		         "https://steamusercontent-a.akamaihd.net/ugc/1014943920262833674/ABA03FB3E5F2BF59D754299BE2A17465616A5AF1/"
    	maps_formula_d["Formula D: Austin"] = 		         "https://steamusercontent-a.akamaihd.net/ugc/1014943920262835411/1480887E772610169EE1DE9454E0E29F07394BBD/"
    	maps_formula_d["Formula D: Nevada"] = 		         "https://steamusercontent-a.akamaihd.net/ugc/1014943920262836221/0624D7A4BF64E7DB01F49C6576EB98CC67DA204C/"
	
    maps_formula_de = {}
    maps_formula_de["Formula De Circuit 01: Monaco"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014192871/5C8AA43D1E01323C398263D03082AE2FC42D1398/"
    maps_formula_de["Formula De Circuit 02: Nederland"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014215260/BDD8C1F05EC950B964D70C0EB4986BE1C841A59F/"
    maps_formula_de["Formula De Circuit 03: Nederland (Alt)"] =    "https://steamusercontent-a.akamaihd.net/ugc/1014943781014221375/52DB634072E8AAE93D36B285BFCD1C152237D6DB/"
    maps_formula_de["Formula De Circuit 04: Belgique"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014223002/7CE0F8C895DB0045E31C904994793890092C0EA3/"
    maps_formula_de["Formula De Circuit 05: South Africa"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014223948/A210BEE7E6EEB0F2D3EEA2276939C998BD376445/"
    maps_formula_de["Formula De Circuit 06: San Marino"] =         "https://steamusercontent-a.akamaihd.net/ugc/1014943781014225294/B2973EF3F6F3A57467544FDC0477AB4BB9975216/"
    maps_formula_de["Formula De Circuit 07: France"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014226766/482BDB94475331B68654476923AD2E950B248779/"
    maps_formula_de["Formula De Circuit 08: Italia"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014227843/62879949672CC8E8D2673044AD9F988AE019BFFF/"
    maps_formula_de["Formula De Circuit 08: Italia (Alt)"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014228765/0C0FE8DF6791BC3FFF1A5F5C36EE2F3DAAFFB707/"
    maps_formula_de["Formula De Circuit 09: Portugal"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014230032/E50644C4B1DAC56CCD66DA9B6E4F4993EC1C7144/"
    maps_formula_de["Formula De Circuit 09: Portugal (Alt)"] =     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014231420/AF8A7A58CE86F4F4E4B902EF7AA51C673EF5A823/"
    maps_formula_de["Formula De Circuit 10: Brasil"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014178841/EDF15683C4595B329A81D1556EA56C698A63139F/"
    maps_formula_de["Formula De Circuit 11: Watkins Glen"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014180219/F03216C7FBD0A90CDE6B9D7370B13374F2F1A7FB/"
    maps_formula_de["Formula De Circuit 12: Silverstone"] =        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014181275/AA880A0E33223A422D27F6579904F1280BF7EC50/"
    maps_formula_de["Formula De Circuit 13: Montreal"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014182629/D461573A84C35FD527BBC2A9687D8A21605E3727/"
    maps_formula_de["Formula De Circuit 14: Long Beach"] =         "https://steamusercontent-a.akamaihd.net/ugc/1014943781014183640/CD919B04DE13F29AAE1E967A9FA3A0CA9FBCBF8A/"
    maps_formula_de["Formula De Circuit 15: Hokenheim"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014184907/DB4BB0B52221D779FA4780B3380EDF5738E12131/"
    maps_formula_de["Formula De Circuit 16: Zeltweg"] =            "https://steamusercontent-a.akamaihd.net/ugc/1014943781014186508/9D314CEB670CCF4E902DD9F3A779CAF1838D94AF/"
    maps_formula_de["Formula De Circuit 17: Buenos Aires"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014187965/6E7CBD9A1EE1575D556A9DD45CEEA59D533368F5/"
    maps_formula_de["Formula De Circuit 18: Barcelona"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014188979/C566F4FE62C63F75032251DA6DAA0C1EE7D01045/"
    maps_formula_de["Formula De Circuit 19: Suzuka"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014191951/1E3677FF7DD28A61A44697DDE3C33FFF6DCA130A/"
    maps_formula_de["Formula De Circuit 20: Melbourne"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014193819/28DA6EBFB42362F7B096E27CB5E7BFC221E869C0/"
    maps_formula_de["Formula De Circuit 20: Melbourne (Alt)"] =    "https://steamusercontent-a.akamaihd.net/ugc/1014943781014194933/D33BCB7751BCE4397C41CDEE808F26D5FAA53531/"
    maps_formula_de["Formula De Circuit 21: Budapest"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014195793/C0AED3930F1C4490B97754F9C43A0FAE74D5C83D/"
    maps_formula_de["Formula De Circuit 21: Budapest (Alt)"] =     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014196757/58314A831EA4A91CF2B111A6E569CD5E1390DBCA/"
    maps_formula_de["Formula De Circuit 22: Nurburgring"] =        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014197709/3D74D37151B3D14BE79A88F176B869015820E29A/"
    maps_formula_de["Formula De Circuit 22: Nurburgring (Alt)"] =  "https://steamusercontent-a.akamaihd.net/ugc/1014943781014198895/687C137A5715E95BBA74749CE741EF42C8C30AD2/"
    maps_formula_de["Formula De Circuit 23: Monterey"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014199986/070DF32A84AB9C7993BD94DE96FDD597D0B8D1DF/"
    maps_formula_de["Formula De Circuit 23: Monterey (Alt)"] =     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014200813/2805713DEE7D651D5C60C33C396A530D3AEDDBE3/"
    maps_formula_de["Formula De Circuit 24: Portland"] =           "https://steamusercontent-a.akamaihd.net/ugc/1014943781014202411/08CF7CD8C796A265B593C6352BAE6791CED85838/"
    maps_formula_de["Formula De Circuit 24: Portland (Alt)"] =     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014203847/CDBFA35519F647C9DED0F84D95CB6B995E4A60AD/"
    maps_formula_de["Formula De Circuit 25: Elkhart"] =            "https://steamusercontent-a.akamaihd.net/ugc/1014943781014204995/5126B8539B6DE15EF9459A804E0217DD6DF323C7/"
    maps_formula_de["Formula De Circuit 26: Indianapolis"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014206321/42BF94A3ED189E1DEE2EBC92A517286F08C2335A/"
    maps_formula_de["Formula De Circuit 26: Indianapolis (Alt)"] = "https://steamusercontent-a.akamaihd.net/ugc/1014943781014207536/65C03910D67AC2F7C39BF778D5F1476072A95B8B/"
    maps_formula_de["Formula De Circuit 27: Detroit"] =            "https://steamusercontent-a.akamaihd.net/ugc/1014943781014208494/C636D56B3BBD896285F57ECA3B1298FD5CE1D24C/"
    maps_formula_de["Formula De Circuit 27: Detroit (Alt)"] =      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014209737/BC6D23BFDCA2B95D623CE1AFCAE08FF5F6409BE8/"
    maps_formula_de["Formula De Circuit 28: Lexington"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014210957/9ECC6A60270203040325661A43E3AACADB528149/"
    maps_formula_de["Formula De Circuit 28: Lexington (Alt)"] =    "https://steamusercontent-a.akamaihd.net/ugc/1014943781014212571/2EC09A3404AFA5A03CDEB28146B377106F4CE3A1/"
    maps_formula_de["Formula De Circuit 29: Atlanta"] =            "https://steamusercontent-a.akamaihd.net/ugc/1014943781014213769/3EE7F17DB34DD989191C3978A7C934DA6A82C764/"
    maps_formula_de["Formula De Circuit 30: Daytona"] =            "https://steamusercontent-a.akamaihd.net/ugc/1014943781014216544/076E54FB5F04369FBECA8501E588A43DF54574CF/"
    maps_formula_de["Formula De Circuit 31: Zhuhai"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014217968/A3AB67B333713B12B9ECBEB9324C9E622A42AD93/"
    maps_formula_de["Formula De Circuit 32: Sepang"] =             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014219065/DBE2EE02890EE9600688D973C4BF4B116B6263D7/"
    maps_formula_de["Formula De Circuit 33: Anniversary"] =        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014220219/95EA2405093E7BFCC66D5C229358CB57964EB49D/"
    maps_formula_de["Extra: Nederland Combined"] =                 "https://steamusercontent-a.akamaihd.net/ugc/1624066328576609278/AD08178E29F88F40016D781A63E515C887807A52/"

    maps_custom = {}
    maps_custom["Autodromo do Algarve"] =                        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014157158/446ADD402A72BF1B155A2BA9A361FA30F19A9D5B/"
    maps_custom["Autodromo Hermanos Rodriguez"] =                "https://steamusercontent-a.akamaihd.net/ugc/1014943781014253264/36646258F24D1D861323AF40287F9CDAFD2F50BD/"
    maps_custom["Autodromo Hermanos Rodriguez (Alt)"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014254576/0748EFCA61EB68134E12BD5EC8027B4362755A6D/"
    maps_custom["Bahrein"] =                                     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014157786/54C2DE37EDAB63C076728FA9ADB53ACECC4A5E7A/"
    maps_custom["Bologna: Centro Storico"] =                     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014163487/F58AD91C5A8DD5626FEFB39EC0C96DD9C318EEE8/"
    maps_custom["Bologna: Stadio Dell'ara"] =                    "https://steamusercontent-a.akamaihd.net/ugc/1014943781014164453/3D1622D58DD64F3F20A3B79B086635753D26D94A/"
    maps_custom["Brands Hatch Circuit"] =                        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014167822/3707831A75D5B3A7CC728E0872160843160762A6/"
    maps_custom["Brands Hatch Circuit (Alt)"] =                  "https://steamusercontent-a.akamaihd.net/ugc/1014943781014165625/C64AAC6DD7D7AD58B1D4DCC5B9B86CE4D04A62DB/"
    maps_custom["Brands Hatch Indy & GP"] =                      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014166870/8EDD31BD907FDC7856BB4E25B1421E6DD64D3146/"
    maps_custom["Burke Lakefront Airport, Ohio"] =               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014169935/61E73150292AE81BDC6FC03A33E9CAA43E41AD62/"
    maps_custom["Canberra 400 Street Circuit"] =                 "https://steamusercontent-a.akamaihd.net/ugc/1014943781014170698/426B4F78EAC0DD8DB8E4FB78C7FCE1FDD91232A5/"
    maps_custom["Castello Sforzesco, Milan"] =                   "https://steamusercontent-a.akamaihd.net/ugc/1014943781014171840/84E88C167E832876C009D2009B5C1B9CFB0E5103/"
    maps_custom["Circuit de Charade, Clermont-Ferrand"] =        "https://steamusercontent-a.akamaihd.net/ugc/1014943781014173126/6E05615E45CFE38A6BB7119A22C8B387D1DDEDD1/"
    maps_custom["Circuit Mont-Tremblant"] =                      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014256791/DD2CBA4BFF3FE65C03BEE6088351E1EF7B80610B/"
    maps_custom["Circuit of the Americas - Austin, Texas"] =     "https://steamusercontent-a.akamaihd.net/ugc/1014943781014174171/4F800A44659DDC6C6E10EBFE8A193F921AD1EEBD/"
    maps_custom["Circuit Urbain de Poitiers"] =                  "https://steamusercontent-a.akamaihd.net/ugc/1014943781014264352/368440BE38E93D4B819A90A79D9B730D304BB5B1/"
    maps_custom["Circuito Interlagos Sao Paulo"] =               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014268545/95753F8C01FD51003DC896E5C740700B1B34357A/"
    maps_custom["Darlington Raceway, South Carolina"] =          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014175843/A1587601F465DC09B93D3CD0AEE2F2A179E37031/"
    maps_custom["Donington Park"] =                              "https://steamusercontent-a.akamaihd.net/ugc/1014943781014177007/A678825EE906F78EAC7103007CD424A458B5023A/"
    maps_custom["Euro Speedway"] =                               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014177919/48E6C96B8C9D25FC25B5685F3F88EFD35D9A9C2F/"
    maps_custom["Fuji Speedway"] =                               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014244920/FD4F1B18288BFB037C4CE7680434A6AD58935DE1/"
    maps_custom["Jerez Circuito de Velocidad"] =                 "https://steamusercontent-a.akamaihd.net/ugc/1014943781014247971/93BE577F7877804256B04C582D0AB4BD10E98205/"
    maps_custom["Le Mans Circuit de la Sarthe"] =                "https://steamusercontent-a.akamaihd.net/ugc/1014943781014248811/D80447C183CF2764ADD5FCAC80D94F2D4A21ABFB/"
    maps_custom["Lowe's Motor Speedway, North Carolina"] =       "https://steamusercontent-a.akamaihd.net/ugc/1014943781014249997/A3B5BC0A74A92AF644B5BD6ABCA43525991B23BB/"
    maps_custom["Mataro"] =                                      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014252118/B6E917AF8F8499AA8956877DCC0613C8A7299B6D/"
    maps_custom["Milwaukee Mile, Wisconsin"] =                   "https://steamusercontent-a.akamaihd.net/ugc/1014943781014255749/B9AE9290639BBD0A4B8874776D9CF95112D51DC2/"
    maps_custom["Nelson Piquet"] =                               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014258946/5D54DE9C91EA77F392D44E6DA25D42A217EF3236/"
    maps_custom["Nice Circuit"] =                                "https://steamusercontent-a.akamaihd.net/ugc/1014943781014259929/B81446AFBF2BC667E8AB166D91FF0F62E566F600/"
    maps_custom["Nurburgring"] =                                 "https://steamusercontent-a.akamaihd.net/ugc/1014943781014260842/724B25B7F315B5B4C717D02ADFD0F348BBEF30EF/"
    maps_custom["Palanga Circuit"] =                             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014262057/C16B53E15A4410B1EAC55A83D0CD019B0A24F9D0/"
    maps_custom["Palermo Marina"] =                              "https://steamusercontent-a.akamaihd.net/ugc/1014943781014251120/5863DEE0E30C898F52AD976DE2CEA741E6D4BF97/"
    maps_custom["Phoenix International Raceway, Arizona"] =      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014263336/C747AD6C7C16CC47BADAFD37AA7DABB2909FA79D/"
    maps_custom["Porto Trieste"] =                               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014265523/B90299EC0F8F16A6B05F365A12B5EA72524A9C8A/"
    maps_custom["Riverside International Raceway, California"] = "https://steamusercontent-a.akamaihd.net/ugc/1014943781014266605/BB03A9E8DA757645FE522481F6BF5D3DEACA3BFA/"
    maps_custom["Roma Colosseo"] =                               "https://steamusercontent-a.akamaihd.net/ugc/1014943781014175057/1462579817F5015154512D85983673BBAEB34444/"
    maps_custom["Roma Isola Tiberina"] =                         "https://steamusercontent-a.akamaihd.net/ugc/1014943781014246851/ADC82EE364DE709D023DCE104EF11EA555E222B9/"
    maps_custom["Rouen - Les Essarts"] =                         "https://steamusercontent-a.akamaihd.net/ugc/1014943781014267554/56F11DD7E8844BB52D064250EA812741C44F2940/"
    maps_custom["Rubber City Raceway, Ohio"] =                   "https://steamusercontent-a.akamaihd.net/ugc/1014943781014154556/2499EB5CCB7C3527B62F1BA22ADD8FC55A6770B9/"
    maps_custom["Silverstone"] =                                 "https://steamusercontent-a.akamaihd.net/ugc/1014943781014269327/26EEDFD2A31E226D1DB8D97BA533B76B56F56C10/"
    maps_custom["Smolensk"] =                                    "https://steamusercontent-a.akamaihd.net/ugc/1014943781014270296/F16BFE50997067EC05A01D513F197AF18A58432A/"
    maps_custom["Snetterton 300 Circuit"] =                      "https://steamusercontent-a.akamaihd.net/ugc/1014943781014271121/239A97A0FFA8D130EC142F507C9B3E0F7624F02F/"
    maps_custom["Toronto Circuit"] =                             "https://steamusercontent-a.akamaihd.net/ugc/1014943781014272302/43A0935AF1EEFCAB04CE1EA3ABBC7950FF2B279D/"
    maps_custom["Twin Ring Motegi"] =                            "https://steamusercontent-a.akamaihd.net/ugc/1014943781014257860/DB56A134512F05460FB362FD75034FEEDE2788FF/"
    maps_custom["Yas Marina Circuit"] =                          "https://steamusercontent-a.akamaihd.net/ugc/1014943781014274103/4E44F452EE04A80CD1B20DEC84791832DF81215B/"
	 
	maps_custom["Cutting Corners"] =                          "https://steamusercontent-a.akamaihd.net/ugc/1014943920263006009/5331A47868AEA4F82386AA59E78365F97FF8168C/"
	maps_custom["Laguna Seca"] =                              "https://steamusercontent-a.akamaihd.net/ugc/1014943920263007094/F10DDFD41ACF699AE0E495982A9CD91A925ED81A/"
	maps_custom["Lime Rock Park"] =                           "https://steamusercontent-a.akamaihd.net/ugc/1014943920263008390/66E32B1FD16B9640411B5E761AD9946578A4A8AC/"
	maps_custom["Los Santos"] =                               "https://steamusercontent-a.akamaihd.net/ugc/1014943920263017313/58B638A8F8BD03580B301429FE9E0DCAB9F11265/"
	maps_custom["Niteroi"] =                                  "https://steamusercontent-a.akamaihd.net/ugc/1014943920263017839/0C65A8966B5F15541372496C3BC7B337268950A6/"
	maps_custom["Rocky Shores"] =                             "https://steamusercontent-a.akamaihd.net/ugc/1014943920263018654/BA45FBD09788223828BF50085DEB56CA45145E4F/"
	maps_custom["Santo Andre"] =                              "https://steamusercontent-a.akamaihd.net/ugc/1014943920263019457/0C830880C7860A76EB0AB63B1EFF587EA1BBF739/"
	maps_custom["Top Gear Test Track"] =                      "https://steamusercontent-a.akamaihd.net/ugc/1014943920263020289/BC8CA96F95A5CB96E629470104ADD6863F415972/"
	maps_custom["Viamao"] =                                   "https://steamusercontent-a.akamaihd.net/ugc/1014943920263021020/F2109A82FA02130E4BC25A3DECF7D7C03DB9760F/"
	
	maps_custom["MK1-GhostValley"] =                                   "https://steamusercontent-a.akamaihd.net/ugc/1290794270354650967/9A30FF7FC979862C01F38B3F8FD3B267FAC1C739/"
	maps_custom["MK2-RainbowRoad"] =                                   "https://steamusercontent-a.akamaihd.net/ugc/1290794270354652267/67F1039B072926EA0E8B594EA3493717EC9C686B/"
	maps_custom["FZ1-BigBlue"] =                                   "https://steamusercontent-a.akamaihd.net/ugc/1290794270354656356/F19A3B1E8EA138EDDAC4CE5CA767B7F6AC48769D/"
	maps_custom["FZ2-WhitePlains"] =                                   "https://steamusercontent-a.akamaihd.net/ugc/1290794270354657528/49AA6080729B000954371ADC7E887A67362B159D/"
	
	maps_custom["PL_Map_001"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825754839/B506D7F299DA436BBD535E2E197C1564A2B0E1B6/"
	maps_custom["PL_Map_002"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825765575/C1B536289A23CCEF03E6760FACF6497840A733C0/"
	maps_custom["PL_Map_003"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825766333/5194BF7EEE47CE04E43A21E9CEA6427009625AD2/"
	maps_custom["PL_Map_004"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825767198/6F851966A07E850DDE0BF974EBF6532071143204/"
	maps_custom["PL_Map_005"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825769267/96EFF62424207F66141B8824A04F272C25F705B3/"
	maps_custom["PL_Map_006"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825770077/9299DAFE59FDF76EEC3AC81E1F1698B6D4518E61/"
	maps_custom["PL_Map_007"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825770709/ACF631364D7B791E08B3746D7C27312B8D8EEF4B/"
	maps_custom["PL_Map_008"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825771653/79B8B7F7294614AE90458D7B3F55162387785F35/"
	maps_custom["PL_Map_009"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825772472/3C5C1777DD54A3347D717F64AC6092EBE5262F98/"
	maps_custom["PL_Map_010"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825773279/7C518F5E404D3976FAF6141189C39B638D0EA28E/"
	maps_custom["PL_Map_011"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825773998/471F8985B468C1BF51962CCF99A71281A63EB2D7/"
	maps_custom["PL_Map_012"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825775120/26AA08B898D09EE10CEEBEBC76B685CA532ACF94/"
	maps_custom["PL_Map_013"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825776010/ACE03C3A41060E00669FBCD31A3945F218675689/"
	maps_custom["PL_Map_014"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825776722/C7770F7E2BCC25203871223331CABB2801956149/"
	maps_custom["PL_Map_015"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825777427/B02D95DEB3D33D0AC08B1821CD7A1CE8EF568A73/"
	maps_custom["PL_Map_016"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825778055/E4CB1B72C92C93264113342B1E730089A82294DA/"
	maps_custom["PL_Map_017"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825779153/C69A3B027C9DF31FAF9799ACCAB5BE0461D95CB6/"
	maps_custom["PL_Map_018"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825780581/7238507334E84DF9BDC562BA2BE96E62A53CC3D1/"
	maps_custom["PL_Map_019"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825781261/9353A0EB2C3BE32B60ACAC2A6BF15D235676A50A/"
	maps_custom["PL_Map_020"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825781918/4C5387AACD479A0D01F561AB337612355F3D13BC/"
	maps_custom["PL_Map_021"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825782484/7391D79FA1F306031B33EADC145780326C051B39/"
	maps_custom["PL_Map_022"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825783023/CF021480E04191722E9CAB2D2040250A9C7D1815/"
	maps_custom["PL_Map_023"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825783722/DDC376259607A373949F516F09824D621D10D7F9/"
	maps_custom["PL_Map_024"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825784414/E7E56E24CD45A732DA9BAD21325A1B9E799003C4/"
	maps_custom["PL_Map_025"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825785031/3969798E07CC6DD38C6559F03D7C79A19AA99A7E/"
	maps_custom["PL_Map_026"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825785619/FD0A303A86745F2892AF183C8830CF1009A067BE/"
	maps_custom["PL_Map_027"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825786078/26F147B0E78118F4D7D9BA9A7E4326E81AC7B3B5/"
	maps_custom["PL_Map_028"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825786992/290296AF745C75CD7A86E0CC4599F2E93914119A/"
	maps_custom["PL_Map_029"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825788035/D1F7C81608D59A50356E54A8A08D39D163740432/"
	maps_custom["PL_Map_030"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825788727/AC26AA393493573D10B4856E80D9F3E223781422/"
	maps_custom["PL_Map_031"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825790114/DB33A423B22E12A8A7D20327CD056D8C4225BE94/"
	maps_custom["PL_Map_032"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825790909/6FF270A53F422C355DA3EB8FFD23123EF084EBE9/"
	maps_custom["PL_Map_033"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825791478/EA63F2B28E5CE9CDE8C64CA2A34B7A50FEC8BA05/"
	maps_custom["PL_Map_034"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825792052/7297B7D6BA4347AB109C125C7540D842E97A0043/"
	maps_custom["PL_Map_035"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825793126/CF7967A6665BD487049A2DFA8A897503711F36EC/"
	maps_custom["PL_Map_036"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825804735/F76C66D91B5BC84F3F4544261D086C898E7B5E37/"
	maps_custom["PL_Map_037"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825806055/AC895518364DC1087FB0AC203C3C6D19F73CF2BF/"
	maps_custom["PL_Map_038"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825806973/FF7D77806A583A5D643DBB12CAD2213DF30B19BF/"
	maps_custom["PL_Map_039"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825807831/EA9E0F46DF1994F5BAE8E839D898219E6148983C/"
	maps_custom["PL_Map_040"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825809018/DC6DDC79239A13343B54F552BE8A8B4F9413E8E6/"
	maps_custom["PL_Map_041"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825809535/B0CF57BF627358622909DFCEAB8DA3FABABCCBFC/"
	maps_custom["PL_Map_042"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825810271/5A3C35302C3FCFD3BBECA25FFA9A741632799CD1/"
	maps_custom["PL_Map_043"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825811036/9D49D307F33494B0EB4A859ECF3103B293696AFC/"
	maps_custom["PL_Map_044"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825811964/FE0CBB367E9754FD218215A36392D40EAE493F58/"
	maps_custom["PL_Map_045"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825813309/22289C6E5346D3FD1D5B1860F7708F5CF9D07790/"
	maps_custom["PL_Map_046"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825814017/85D200C7D0528F280470ED106E3BF0CC1D4D46BF/"
	maps_custom["PL_Map_047"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825815367/B9A489B95A4DA797BE70DB258D5394B2341E1024/"
	maps_custom["PL_Map_048"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825816100/18B8FDA88525768812432CA11C8AE2C06B091E24/"
	maps_custom["PL_Map_049"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825817530/C5E602E09AFFB62097F52276C6035FF726FD8A9F/"
	maps_custom["PL_Map_050"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825818357/6253769CC832917A7FC805ADD5C468ACC98CFEF0/"
	maps_custom["PL_Map_051"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825819184/47019E9390041859964F3B79400A53A3F5B5CE17/"
	maps_custom["PL_Map_052"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825820118/F4C05488D6AFA2802961DBA599CD68A74B9F0FFA/"
	maps_custom["PL_Map_053"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825820971/2209D1F9D0C2E1140E2B16A56DAE2EFD6FEEA73A/"
	maps_custom["PL_Map_054"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825822294/930C009900B5A19C5958F66F6CD5318CADF9B6B0/"
	maps_custom["PL_Map_055"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825823076/F8DD5CE9E376E7FB066F935E870D46D65E4D9C54/"
	maps_custom["PL_Map_056"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825824344/538B74BDD53E101D72B8AE72063E8BC3B3F3C5AD/"
	maps_custom["PL_Map_057"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825825578/BEB1C01353375F5AD13340884D1ED47D27716625/"
	maps_custom["PL_Map_058"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825826512/8E30420ED8E848B126C894435B8321B1CDA42772/"
	maps_custom["PL_Map_059"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825828321/328CB56E4A44E26B8B0B36B267D33C82B4ACFDB1/"
	maps_custom["PL_Map_060"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825829059/200ABDDF7A673070E1FD0541330D085BC3C3565D/"
	maps_custom["PL_Map_061"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825829748/DD3B31A3547185D2D3956187E45E81D6B541B75A/"
	maps_custom["PL_Map_062"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825830387/9D08113208C5B29B70BC4B3880F741741ADB3FA5/"
	maps_custom["PL_Map_063"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825830945/5213BD56C7C938F072A7DC697DA36222BA1D9D5E/"
	maps_custom["PL_Map_064"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825831947/5BCB45E84C5831BF59440F6A4EDD2097EFB3F90F/"
	maps_custom["PL_Map_065"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825832506/639556340E32D59C29B25C0051A4E2316BF0DC39/"
	maps_custom["PL_Map_066"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825833582/B65ABBBB2BA543BB87F54F5E0AC762BD4B4DDB92/"
	maps_custom["PL_Map_067"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825834193/8919F9D26F822356ACC652E5DC3F9024E307BC2A/"
	maps_custom["PL_Map_068"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825834977/4C13D0BD4DB2B917A635855FDC0C23A8CE165049/"
	maps_custom["PL_Map_069"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825835951/009F3BCF8C95DCC6EDD9E898E750559412F0BF98/"
	maps_custom["PL_Map_070"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825836678/14CB8991D279038306AEF2CB09E686917CE9F765/"
	maps_custom["PL_Map_071"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825837230/B9FF4513A3E02F2CAAE6D9F2431026A8525B5ECC/"
	maps_custom["PL_Map_072"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825837874/00CB57C24086FE13B736DA4555DF8BCCE2C10F81/"
	maps_custom["PL_Map_073"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825837874/00CB57C24086FE13B736DA4555DF8BCCE2C10F81/"
	maps_custom["PL_Map_074"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825839321/90510D77FE8DE3E0976A2102B9294DECD54157DC/"
	maps_custom["PL_Map_075"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366236825839979/5C6344085FA81EFE0349B4F0E54BDFE9FFA3F538/"
	maps_custom["PL_Map_076"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872619572/72D7A39232B9CBC3D04A27B1E939AAC5C9514871/"
	maps_custom["PL_Map_077"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872620684/462F6464300A91B4F0D3C0525E4B94E695072F4F/"
	maps_custom["PL_Map_078"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872622021/99CFD077E06017A790F3F6CE299B5B445DCA0EDA/"
	maps_custom["PL_Map_079"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872623005/A33737F7E6559D0457900D2971497D1343DE2E16/"
	maps_custom["PL_Map_080"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872623680/BD8D7255A287861319C10AB1A290E2E22CF9AF3A/"
	maps_custom["PL_Map_081"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872624288/F078FA2F968F4F0DD38126ED79A056BE65277FD6/"
	maps_custom["PL_Map_082"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872625369/124B87DF5DAEF8CD055EEAC64B26565B58E344E0/"
	maps_custom["PL_Map_083"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872626443/C202BDBEC4199E9D3A7ACB2C86BEB6BA1F3FD95E/"
	maps_custom["PL_Map_084"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872627404/EEE25BFB4A72C3C87394F140B5D80ED881B9CDBF/"
	maps_custom["PL_Map_085"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872628608/AC0FBA2D618A9ACCE5D422ADAEB588EC0359E857/"
	maps_custom["PL_Map_086"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872629470/DCD5FC692B55906D1610CF56839BDB233FEC2F3F/"
	maps_custom["PL_Map_087"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872630233/B1AB2184E59026BEC99E1B6CEAFDFBD8E1908CCF/"
	maps_custom["PL_Map_088"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872630994/5F93949D53BD23E9FC9141B21C7EF01B8A67293E/"
	maps_custom["PL_Map_089"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872631835/CBB3271E454E566A32B5DA65925A7BD5BF729B2D/"
	maps_custom["PL_Map_090"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872632731/5DC8BEFA7E2940E0DC5E32626F4654FD323B2E10/"
	maps_custom["PL_Map_091"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872633599/CA9C825AAA7DCD8F5D15BC03BF1DAEB23DDC4D7B/"
	maps_custom["PL_Map_092"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872634431/107F988CD69B2919F18D251D2748B64F7D50B04C/"
	maps_custom["PL_Map_093"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872635700/3F37D9B8B3E12F0BB8DA96FD30A4667315448485/"
	maps_custom["PL_Map_094"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872636634/56BA9D1BE9960B4C0549EADCB0281001430AA1CA/"
	maps_custom["PL_Map_095"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872641700/8343A51DF470AB20A76EEC1119CF02EC0C1CAAF8/"
	maps_custom["PL_Map_096"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872643059/A922B9043AE45880C227A3527CD93FE81FF1C33E/"
	maps_custom["PL_Map_097"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872644488/1CC3EC400C6A83809EE79754EB5FAC13345F3403/"
	maps_custom["PL_Map_098"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872645494/AA24FE0C89E61E308E9FB6E9CB0D295EEBC2F137/"
	maps_custom["PL_Map_099"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872646326/6D20B5D1675B4BFC5F343C74ECE92B046CE040AB/"
	maps_custom["PL_Map_100"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872647542/C178DA17DCAAF8D2144E44DEDE5FC7C8269ED537/"
	maps_custom["PL_Map_101"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872648504/B37C820E1B3571795717A7975C5BF4919B414994/"
	maps_custom["PL_Map_102"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872649528/8FE5B2F5B9C61C7C067F8985ADA1CA5114E955C9/"
	maps_custom["PL_Map_103"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872650302/72BC04D2623C754464E8BA86E2375B65DC36ED1F/"
	maps_custom["PL_Map_104"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872653800/BFD23943446326262AE89D5320B35F9536E304F5/"
	maps_custom["PL_Map_105"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872654872/A433B05B50B933869AFCE54B074437241A4F1C49/"
	maps_custom["PL_Map_106"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872656030/BE85D95774201A3C293F66B8B452FF5D19E1136E/"
	maps_custom["PL_Map_107"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872657146/A9587040243CF8A0710A5F7F3BFD09EFF18FC5A3/"
	maps_custom["PL_Map_108"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872657915/812D4481BA3DF4273F57A743212D53EA7A9F5A1E/"
	maps_custom["PL_Map_109"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872658708/28460B846AC925624F1F3B6BAF4D56562CBD3510/"
	maps_custom["PL_Map_110"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872659560/64A14BF07CC58374B48A9153410D3988289E6424/"
	maps_custom["PL_Map_111"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872660732/5B1EDF9AF89E08ACA0382E4C44E3FD3BDCC8BA42/"
	maps_custom["PL_Map_112"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872661841/F01E5B6016D66B85A2C2E0839FE885B6CA9D05A2/"
	maps_custom["PL_Map_113"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872662725/BA01F2AD29BBB9019EE1BAA7521CC180EE1095F0/"
	maps_custom["PL_Map_114"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872663574/CB0871C7215EE952871C7C2B25421BE348559871/"
	maps_custom["PL_Map_115"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872664384/5675B3F3EA25A5EF4D838953D2D6EB79C5A354F3/"
	maps_custom["PL_Map_116"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872665705/E0982A5788308FF3A7F47BFAF977803883CC473F/"
	maps_custom["PL_Map_117"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872666573/24B62C6F8262872B673AF43CE54AD2EE4B0D7E32/"
	maps_custom["PL_Map_118"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872667539/5589BADF4709E64A1078DCFE85F8339F425772BE/"
	maps_custom["PL_Map_119"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872668646/1427B10ED9DE2F2A407CC9A0BF763DDE0EF80EE2/"
	maps_custom["PL_Map_120"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872669503/87BFE681E75AF1256C72A70D77A4BBFE615C08C0/"
	maps_custom["PL_Map_121"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872670170/A590731394707EF72CB94B79D098C1F4DB2F6B61/"
	maps_custom["PL_Map_122"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872670852/15183EFDA45BEAD1E25FEEAE03A794B92F953121/"
	maps_custom["PL_Map_123"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872671505/048560601A2967F975C15225104870FD5070E7C5/"
	maps_custom["PL_Map_124"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872672165/4A4098B567485A07290DE1B8244CB443EEFD1E72/"
	maps_custom["PL_Map_125"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872673296/A6F7FC5D87A62DBE7D671DB5E46D96B5A1F6F456/"
	maps_custom["PL_Map_126"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872674067/B265F620EDF59819713995372BF68E08E6090221/"
	maps_custom["PL_Map_127"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872675101/7BD544EB5AA70B29E9A1ECF57A4CBFA067F244A4/"
	maps_custom["PL_Map_128"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872675858/B7981BDBB9DA58F90F1D73AA65A29A8ADC86B3E4/"
	maps_custom["PL_Map_129"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872676613/9B390441C3EBDE3BAB8E2F9AE1AD045C81323637/"
	maps_custom["PL_Map_130"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872677449/1AE669C6A7E002C5CA70B1E06C61B4AEED9401F9/"
	maps_custom["PL_Map_131"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872678227/94CA75208DB133D520B3758989FFE8D0A610E782/"
	maps_custom["PL_Map_132"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872678862/3414D583615672F96AE79F0A9299C5652832C9D6/"
	maps_custom["PL_Map_133"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872679817/218B6B6CDFCD93390CC061C905473D8769205DA4/"
	maps_custom["PL_Map_134"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872680744/E78DBBD50DD4BB6FDB8440521EE208791258DCD4/"
	maps_custom["PL_Map_135"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872681270/4D51ED683B78F2301ED6948182F293BCD2ADCA8A/"
	maps_custom["PL_Map_136"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872681928/E13641440A66C6D6006C35262D2D993C3CD3EE8B/"
	maps_custom["PL_Map_137"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872682498/4F124AC4D4B5F783633676886DBCF1771F5D3E0D/"
	maps_custom["PL_Map_138"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872683439/4A8C645CD6BDE940515D4A48464257600BBA8DD7/"
	maps_custom["PL_Map_139"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872684233/8B19E0C4678264804EFF7287399482A4CDB0D79C/"
	maps_custom["PL_Map_140"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872685068/FBAD6AB2C647AECF13CE9AD2E5291AE85E4F66B6/"
	maps_custom["PL_Map_141"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872685899/4BB9A435E8417D227C27D9806F11C901DE844EF1/"
	maps_custom["PL_Map_142"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872686476/300B1D59A000C1B4E3C568B53CC61D5E630C825E/"
	maps_custom["PL_Map_143"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872687226/BF7AEEE0522D9A01FCB1EA2F7C0EF6DEF3F99EE8/"
	maps_custom["PL_Map_144"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872688015/36B0901580A4FB84DBFECB7516723B41AD4EEFDE/"
	maps_custom["PL_Map_145"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872688936/AEC2FC0B6ABA2771BBE7AA0F53DF6ACE60F23554/"
	maps_custom["PL_Map_146"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872689897/51B17A9AB959A127F7CE33B441A5A4B6CBC1C599/"
	maps_custom["PL_Map_147"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872690844/F50864FD29B553DFFD63DA2078AD5039842A823C/"
	maps_custom["PL_Map_148"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872691699/EB329240B157D07A392AD3CF0ECB81A524D2A4C7/"
	maps_custom["PL_Map_149"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872692379/774890EC9D8CD42C82E7088F7A51354B7DFA03E8/"
	maps_custom["PL_Map_150"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872693013/211FDABA48A22D0484833ECD6E6E0851E4759F4D/"
	maps_custom["PL_Map_151"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872693659/C4F9ABDA44B758D747A109D3A16D9DC81091AC12/"
	maps_custom["PL_Map_152"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872694434/1F9F8CE7258BAB451BE8EA4F8CDC52CCE89A2514/"
	maps_custom["PL_Map_153"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872695163/4047332C36AB79C773C3353A11156ACABC1F6F56/"
	maps_custom["PL_Map_154"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872695864/8167E15A99C134EF7352B1759AFA419FFE1E96EF/"
	maps_custom["PL_Map_155"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872696487/542936FFD38117337FB85849E27BADC679201FCA/"
	maps_custom["PL_Map_156"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872697472/FBA4DF83F76AD309237685BA4CFA6A99F294BC14/"
	maps_custom["PL_Map_157"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872698084/27F81BB3EA3F7AE9BDAFEBC90E372F5920559CE9/"
	maps_custom["PL_Map_158"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872698786/7D9047D608752F9C95FF255353CED32C186EC219/"
	maps_custom["PL_Map_159"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872699382/D77DDB29BF47481F1B8757C60333BB196537C22C/"
	maps_custom["PL_Map_160"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872699950/7EE56EFCE19CE4B1A284B73F647D74C093FA4BF4/"
	maps_custom["PL_Map_161"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872700603/767F02FABD79784B91383688B513EFC39DAC0FC4/"
	maps_custom["PL_Map_162"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872701202/FA890A457673E92D0D206C584842FC8263C45E3D/"
	maps_custom["PL_Map_163"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872701832/7477B86E5B0BC6C362361F995C80B7FBE3D99342/"
	maps_custom["PL_Map_164"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872702543/C9501B103AF4DD5DB91D8389833F97710FE8211C/"
	maps_custom["PL_Map_165"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872703100/92749CBD57A433AF617351EB34B7B607132153ED/"
	maps_custom["PL_Map_166"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872703898/7D3A5591028802D7F1C17824ADD1A8049D3F822A/"
	maps_custom["PL_Map_167"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872704866/DE4D4A5331B692115215A97067E5DE3399604093/"
	maps_custom["PL_Map_168"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872705500/BC5BDB7E315191921E20C3D31D69F8C4F0AD3938/"
	maps_custom["PL_Map_169"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872706989/2DED96E22ABB97DD04C8B4B5BCCE7F2B170A7FD0/"
	maps_custom["PL_Map_170"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872707800/047349EF4209A9469A2DF15FB807593454C21360/"
	maps_custom["PL_Map_171"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872708403/4A7B3272A108E272074D65577D1D90F7A0C55028/"
	maps_custom["PL_Map_172"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872708938/03C852782F3AD93FF141381D5D375B963D87786D/"
	maps_custom["PL_Map_173"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872709470/7ABFA69FDCD9384F68E7E9F0AECE91ECDAA4291A/"
	maps_custom["PL_Map_174"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872717580/DE146D4409492C79FF801012B964B4429C494691/"
	maps_custom["PL_Map_175"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872718231/A1B7616D2E27F5D768C4B4492AB1A9545480F7DD/"
	maps_custom["PL_Map_176"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872718885/DAF0023EA3CB988A3F609CDD2CF911A1E2CEFFA5/"
	maps_custom["PL_Map_177"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872719502/6FF2AFB37BCADC014976CC8FE6AE837219B140C9/"
	maps_custom["PL_Map_178"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872720034/9CB90486F595B9BDFDA424F251F8F3D64446A081/"
	maps_custom["PL_Map_179"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872721655/80A9998E3FA427031EDC840ABC0B431E0173B929/"
	maps_custom["PL_Map_180"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872722559/4E0F7298616CB50DD24E1913F7DE83AEDDC8DFDA/"
	maps_custom["PL_Map_181"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872723487/D8E119F48C44B42CD60E953A0F8843A66AEABFF6/"
	maps_custom["PL_Map_182"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872724357/19A69BD3E699A252EB2060880DACFAB94D577145/"
	maps_custom["PL_Map_183"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872724965/8DA5D37E73EE32377B9162D44F386FD4A45B305C/"
	maps_custom["PL_Map_184"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872725786/F716DC6DEB1A49098864E0F09D880FC9FFA6A84C/"
	maps_custom["PL_Map_185"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872726482/FB81D805F2ADDF056DD65E8CD877BE3EB344B562/"
	maps_custom["PL_Map_186"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872727339/101F18C894B0F7B0C5F93CB45D920BEF11D19181/"
	maps_custom["PL_Map_187"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872727961/B0AAC053722037B876C16B761C46E102F4682D9A/"
	maps_custom["PL_Map_188"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872728756/6B1145CCEF7BDB335943DFC12575A573445002AE/"
	maps_custom["PL_Map_189"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872729878/B0DCFCA5483BD0EF411DEECBF7154C365D497E3E/"
	maps_custom["PL_Map_190"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872730462/2265443A4DDB56EA8A7E5B84B1A7EC48815C3398/"
	maps_custom["PL_Map_191"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872731274/578EB9CDB66F053A3C7B1AA671E93424C004D1AD/"
	maps_custom["PL_Map_192"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872731909/F312553305126483874B2CDA3DE8436D66CC4CAD/"
	maps_custom["PL_Map_193"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872732461/EE6A078FC8F33970EB017DF1779BE68EA9D670A2/"
	maps_custom["PL_Map_194"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872733145/346DA3622048A6BED008ED3A605114973F95BBAE/"
	maps_custom["PL_Map_195"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872733888/70D781FAEBF7BFC1F53DD4BF227F4DF1F2015345/"
	maps_custom["PL_Map_196"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872734463/D6216D23BA14ACCA213255CF69D5B46C8A0F8519/"
	maps_custom["PL_Map_197"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872735077/42B5A466225B7C42E7FEA7AC95472DEB64B94DB2/"
	maps_custom["PL_Map_198"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872735744/70D4306EFF5C69D06C5056ADC81CD36929BFB40E/"
	maps_custom["PL_Map_199"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872736714/3FF25B04895D1A845212F8AED5304C76ED796CF8/"
	maps_custom["PL_Map_200"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872737383/1B7BA74385C8A14AF19BF560E8FC869319A134BC/"
	maps_custom["PL_Map_201"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872738070/1A12F8903A2EF93C9E0FA6F40135DF11984AB908/"
	maps_custom["PL_Map_202"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872738704/D64509465D8ED53C4CB656AD08BEF510B92B6734/"
	maps_custom["PL_Map_203"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872739260/07A3E75DC23B41F61AB69236CA6C06276DD75C59/"
	maps_custom["PL_Map_204"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872739892/706C7865EA4C4F6D122229A1299192824FF18654/"
	maps_custom["PL_Map_205"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872740577/ECBD6E23DBD64FF9CC80EF90929CF6A40EF8020B/"
	maps_custom["PL_Map_206"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872741206/D90023B3CD451497E910321908D63FC1777B8992/"
	maps_custom["PL_Map_207"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872741820/763376802709BBD39FEE15F51DF0D43A6FC320AC/"
	maps_custom["PL_Map_208"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872742426/BDE674C889BB7663C417508A9AAA5017CFFAC2AD/"
	maps_custom["PL_Map_209"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872743278/8B2A8CAD6EEC8F5678EF96ACB416C328B7AE7706/"
	maps_custom["PL_Map_210"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872743942/2485F10C58B203EAD5A1D55DC693F011FFC146E8/"
	maps_custom["PL_Map_211"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872744436/84D8152D52341C1820F9CE471623AB1EEAD36BE5/"
	maps_custom["PL_Map_212"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872745215/8EE28D1D4FC372C083DC15D3FEC72F2ECED59210/"
	maps_custom["PL_Map_213"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872746275/ED69D42D110767486E7C04F2718394F414EC6E16/"
	maps_custom["PL_Map_214"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872747053/36A20BBABDACBD24E6FDF9FF077D4EA3298A5B72/"
	maps_custom["PL_Map_215"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872750274/C79154E536DD74EE720312E8D72C2DD8607E71C5/"
	maps_custom["PL_Map_216"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872751258/2E5417488110BDD217BC6998AB3D8C00F62D110C/"
	maps_custom["PL_Map_217"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872751851/C207A54DEF94591FD49E3CF1B17FD41AF334B5FF/"
	maps_custom["PL_Map_218"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872752437/2D9A1703A292C53C874F724E8FEEBE21733C6A0C/"
	maps_custom["PL_Map_219"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872753177/5F59E7AA82A168CFF5A69FE8E3E33CE541571ADC/"
	maps_custom["PL_Map_220"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872753854/2080ADC6CB91AA8DBEFC61FC0497E22BD00FC3BC/"
	maps_custom["PL_Map_221"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872754596/63CA79A48DC34F8B43E286D0F946F42014B8BCBF/"
	maps_custom["PL_Map_222"] = "https://steamusercontent-a.akamaihd.net/ugc/1680366396872755115/293DA8FAB42B436D81EEC76C1B4387DA5CA4F425/"
	
    returnToMenu()
end

do -- #region: setup functions

	-- Formula D Maps

    function setupFDMonaco(player, elementID)
        setMapImage(maps_formula_d["Formula D: Monaco"])
    end
    
    function setupFDRaceCity(player, elementID)
        setMapImage(maps_formula_d["Formula D: Race City"])
    end
    
    function setupFDRaceCityAlt(player, elementID)
        setMapImage(maps_formula_d["Formula D: Race City (Alt)"])
    end
    
    function setupFDSebring(player, elementID)
        setMapImage(maps_formula_d["Formula D: Sebring"])
    end
    
    function setupFDChicago(player, elementID)
        setMapImage(maps_formula_d["Formula D: Chicago"])
    end
    
    function setupFDHockenheim(player, elementID)
        setMapImage(maps_formula_d["Formula D: Hockenheim"])
    end
    
    function setupFDValencia(player, elementID)
        setMapImage(maps_formula_d["Formula D: Valencia"])
    end
    
    function setupFDDocks(player, elementID)
        setMapImage(maps_formula_d["Formula D: Docks"])
    end
    
    function setupFDDocksAlt(player, elementID)
        setMapImage(maps_formula_d["Formula D: Docks (Alt)"])
    end
    
    function setupFDSingapore(player, elementID)
        setMapImage(maps_formula_d["Formula D: Singapore"])
    end
	
	function setupFDBaltimore(player, elementID)
        setMapImage(maps_formula_d["Formula D: Baltimore"])
    end
	
	function setupFDBuddh(player, elementID)
        setMapImage(maps_formula_d["Formula D: Buddh"])
    end
	
	function setupFDNewJersey(player, elementID)
        setMapImage(maps_formula_d["Formula D: New Jersey"])
    end
	
	function setupFDSotchi(player, elementID)
        setMapImage(maps_formula_d["Formula D: Sotchi"])
    end
	
	function setupFDAustin(player, elementID)
        setMapImage(maps_formula_d["Formula D: Austin"])
    end
	
	function setupFDNevada(player, elementID)
        setMapImage(maps_formula_d["Formula D: Nevada"])
    end
    
	-- Formula De Maps
	
	function setupFDe01(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 01: Monaco"])
    end

    function setupFDe02(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 02: Nederland"])
    end

    function setupFDe03(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 03: Nederland (Alt)"])
    end

    function setupFDe04(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 04: Belgique"])
    end

    function setupFDe05(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 05: South Africa"])
    end

    function setupFDe06(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 06: San Marino"])
    end

    function setupFDe07(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 07: France"])
    end

    function setupFDe08a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 08: Italia"])
    end

    function setupFDe08b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 08: Italia (Alt)"])
    end

    function setupFDe09a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 09: Portugal"])
    end

    function setupFDe09b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 09: Portugal (Alt)"])
    end

    function setupFDe10(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 10: Brasil"])
    end

    function setupFDe11(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 11: Watkins Glen"])
    end

    function setupFDe12(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 12: Silverstone"])
    end

    function setupFDe13(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 13: Montreal"])
    end

    function setupFDe14(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 14: Long Beach"])
    end

    function setupFDe15(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 15: Hokenheim"])
    end

    function setupFDe16(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 16: Zeltweg"])
    end

    function setupFDe17(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 17: Buenos Aires"])
    end

    function setupFDe18(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 18: Barcelona"])
    end

    function setupFDe19(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 19: Suzuka"])
    end

    function setupFDe20a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 20: Melbourne"])
    end

    function setupFDe20b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 20: Melbourne (Alt)"])
    end

    function setupFDe21a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 21: Budapest"])
    end

    function setupFDe21b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 21: Budapest (Alt)"])
    end

    function setupFDe22a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 22: Nurburgring"])
    end

    function setupFDe22b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 22: Nurburgring (Alt)"])
    end

    function setupFDe23a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 23: Monterey"])
    end

    function setupFDe23b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 23: Monterey (Alt)"])
    end

    function setupFDe24a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 24: Portland"])
    end

    function setupFDe24b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 24: Portland (Alt)"])
    end

    function setupFDe25(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 25: Elkhart"])
    end

    function setupFDe26a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 26: Indianapolis"])
    end

    function setupFDe26b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 26: Indianapolis (Alt)"])
    end

    function setupFDe27a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 27: Detroit"])
    end

    function setupFDe27b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 27: Detroit (Alt)"])
    end

    function setupFDe28a(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 28: Lexington"])
    end

    function setupFDe28b(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 28: Lexington (Alt)"])
    end

    function setupFDe29(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 29: Atlanta"])
    end

    function setupFDe30(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 30: Daytona"])
    end

    function setupFDe31(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 31: Zhuhai"])
    end

    function setupFDe32(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 32: Sepang"])
    end

    function setupFDe33(player, elementID)
        setMapImage(maps_formula_de["Formula De Circuit 33: Anniversary"])
    end

    function setupFDe34(player, elementID)
        setMapImage(maps_formula_de["Extra: Nederland Combined"])
    end
	
	-- Custom Maps
	
	function setupAkron(player, elementID)
        setMapImage(maps_custom["Rubber City Raceway, Ohio"])
    end
    function setupAlgarve(player, elementID)
        setMapImage(maps_custom["Autodromo do Algarve"])
    end
    function setupBahrein(player, elementID)
        setMapImage(maps_custom["Bahrein"])
    end
    function setupBolognaCentro(player, elementID)
        setMapImage(maps_custom["Bologna: Centro Storico"])
    end
    function setupBolognaStadio(player, elementID)
        setMapImage(maps_custom["Bologna: Stadio Dell'ara"])
    end
    function setupBrandsHatch(player, elementID)
        setMapImage(maps_custom["Brands Hatch Circuit"])
    end
    function setupBrandsHatchAlt(player, elementID)
        setMapImage(maps_custom["Brands Hatch Circuit (Alt)"])
    end
    function setupBrandsHatchIndyGP(player, elementID)
        setMapImage(maps_custom["Brands Hatch Indy & GP"])
    end
    function setupBurke(player, elementID)
        setMapImage(maps_custom["Burke Lakefront Airport, Ohio"])
    end
    function setupCanberra(player, elementID)
        setMapImage(maps_custom["Canberra 400 Street Circuit"])
    end
    function setupCastello(player, elementID)
        setMapImage(maps_custom["Castello Sforzesco, Milan"])
    end
    function setupCircuitdeCharade(player, elementID)
        setMapImage(maps_custom["Circuit de Charade, Clermont-Ferrand"])
    end
    function setupCircuitoftheAmericas(player, elementID)
        setMapImage(maps_custom["Circuit of the Americas - Austin, Texas"])
    end
    function setupColosseum(player, elementID)
        setMapImage(maps_custom["Roma Colosseo"])
    end
    function setupDarlington(player, elementID)
        setMapImage(maps_custom["Darlington Raceway, South Carolina"])
    end
    function setupDonington(player, elementID)
        setMapImage(maps_custom["Donington Park"])
    end
    function setupEuroSpeedway(player, elementID)
        setMapImage(maps_custom["Euro Speedway"])
    end
    function setupFuji(player, elementID)
        setMapImage(maps_custom["Fuji Speedway"])
    end
    function setupIsolaTiberina(player, elementID)
        setMapImage(maps_custom["Roma Isola Tiberina"])
    end
    function setupJerez(player, elementID)
        setMapImage(maps_custom["Jerez Circuito de Velocidad"])
    end
    function setupLeMans(player, elementID)
        setMapImage(maps_custom["Le Mans Circuit de la Sarthe"])
    end
    function setupLowes(player, elementID)
        setMapImage(maps_custom["Lowe's Motor Speedway, North Carolina"])
    end
    function setupMarina(player, elementID)
        setMapImage(maps_custom["Palermo Marina"])
    end
    function setupMataro(player, elementID)
        setMapImage(maps_custom["Mataro"])
    end
    function setupMexicoCity(player, elementID)
        setMapImage(maps_custom["Autodromo Hermanos Rodriguez"])
    end
    function setupMexicoCity2(player, elementID)
        setMapImage(maps_custom["Autodromo Hermanos Rodriguez (Alt)"])
    end
    function setupMilwaukee(player, elementID)
        setMapImage(maps_custom["Milwaukee Mile, Wisconsin"])
    end
    function setupMontTremblant(player, elementID)
        setMapImage(maps_custom["Circuit Mont-Tremblant"])
    end
    function setupMotegi(player, elementID)
        setMapImage(maps_custom["Twin Ring Motegi"])
    end
    function setupNelsonPiquet(player, elementID)
        setMapImage(maps_custom["Nelson Piquet"])
    end
    function setupNice(player, elementID)
        setMapImage(maps_custom["Nice Circuit"])
    end
    function setupNurburgring(player, elementID)
        setMapImage(maps_custom["Nurburgring"])
    end
    function setupPalanga(player, elementID)
        setMapImage(maps_custom["Palanga Circuit"])
    end
    function setupPhoenix(player, elementID)
        setMapImage(maps_custom["Phoenix International Raceway, Arizona"])
    end
    function setupPoitiers(player, elementID)
        setMapImage(maps_custom["Circuit Urbain de Poitiers"])
    end
    function setupPortoTrieste(player, elementID)
        setMapImage(maps_custom["Porto Trieste"])
    end
    function setupRiverside(player, elementID)
        setMapImage(maps_custom["Riverside International Raceway, California"])
    end
    function setupRouenLesEssarts(player, elementID)
        setMapImage(maps_custom["Rouen - Les Essarts"])
    end
    function setupSaoPaulo(player, elementID)
        setMapImage(maps_custom["Circuito Interlagos Sao Paulo"])
    end
    function setupSilverstone(player, elementID)
        setMapImage(maps_custom["Silverstone"])
    end
    function setupSmolensk(player, elementID)
        setMapImage(maps_custom["Smolensk"])
    end
    function setupSnetterton(player, elementID)
        setMapImage(maps_custom["Snetterton 300 Circuit"])
    end
    function setupToronto(player, elementID)
        setMapImage(maps_custom["Toronto Circuit"])
    end
    function setupYasMarina(player, elementID)
        setMapImage(maps_custom["Yas Marina Circuit"])
    end
	
	function setupCuttingCorners(player, elementID)
        setMapImage(maps_custom["Cutting Corners"])
    end
	function setupLagunaSeca(player, elementID)
        setMapImage(maps_custom["Laguna Seca"])
    end
	function setupLimeRockPark(player, elementID)
        setMapImage(maps_custom["Lime Rock Park"])
    end
	function setupLosSantos(player, elementID)
        setMapImage(maps_custom["Los Santos"])
    end
	function setupNiteroi(player, elementID)
        setMapImage(maps_custom["Niteroi"])
    end
	function setupRockyShores(player, elementID)
        setMapImage(maps_custom["Rocky Shores"])
    end
	function setupSantoAndre(player, elementID)
        setMapImage(maps_custom["Santo Andre"])
    end
	function setupTopGearTestTrack(player, elementID)
        setMapImage(maps_custom["Top Gear Test Track"])
    end
	function setupViamao(player, elementID)
        setMapImage(maps_custom["Viamao"])
    end
	function setupMK1GhostValley(player, elementID)
        setMapImage(maps_custom["MK1-GhostValley"])
    end
	function setupMK2RainbowRoad(player, elementID)
        setMapImage(maps_custom["MK2-RainbowRoad"])
    end
	function setupFZ1BigBlue(player, elementID)
        setMapImage(maps_custom["FZ1-BigBlue"])
    end
	function setupFZ2WhitePlains(player, elementID)
        setMapImage(maps_custom["FZ2-WhitePlains"])
    end
	
	function setupPL_Map_001(player, elementID)
		setMapImage(maps_custom["PL_Map_001"])
	end

	function setupPL_Map_002(player, elementID)
		setMapImage(maps_custom["PL_Map_002"])
	end

	function setupPL_Map_003(player, elementID)
		setMapImage(maps_custom["PL_Map_003"])
	end

	function setupPL_Map_004(player, elementID)
		setMapImage(maps_custom["PL_Map_004"])
	end

	function setupPL_Map_005(player, elementID)
		setMapImage(maps_custom["PL_Map_005"])
	end

	function setupPL_Map_006(player, elementID)
		setMapImage(maps_custom["PL_Map_006"])
	end

	function setupPL_Map_007(player, elementID)
		setMapImage(maps_custom["PL_Map_007"])
	end

	function setupPL_Map_008(player, elementID)
		setMapImage(maps_custom["PL_Map_008"])
	end

	function setupPL_Map_009(player, elementID)
		setMapImage(maps_custom["PL_Map_009"])
	end

	function setupPL_Map_010(player, elementID)
		setMapImage(maps_custom["PL_Map_010"])
	end

	function setupPL_Map_011(player, elementID)
		setMapImage(maps_custom["PL_Map_011"])
	end

	function setupPL_Map_012(player, elementID)
		setMapImage(maps_custom["PL_Map_012"])
	end

	function setupPL_Map_013(player, elementID)
		setMapImage(maps_custom["PL_Map_013"])
	end

	function setupPL_Map_014(player, elementID)
		setMapImage(maps_custom["PL_Map_014"])
	end

	function setupPL_Map_015(player, elementID)
		setMapImage(maps_custom["PL_Map_015"])
	end

	function setupPL_Map_016(player, elementID)
		setMapImage(maps_custom["PL_Map_016"])
	end

	function setupPL_Map_017(player, elementID)
		setMapImage(maps_custom["PL_Map_017"])
	end

	function setupPL_Map_018(player, elementID)
		setMapImage(maps_custom["PL_Map_018"])
	end

	function setupPL_Map_019(player, elementID)
		setMapImage(maps_custom["PL_Map_019"])
	end

	function setupPL_Map_020(player, elementID)
		setMapImage(maps_custom["PL_Map_020"])
	end

	function setupPL_Map_021(player, elementID)
		setMapImage(maps_custom["PL_Map_021"])
	end

	function setupPL_Map_022(player, elementID)
		setMapImage(maps_custom["PL_Map_022"])
	end

	function setupPL_Map_023(player, elementID)
		setMapImage(maps_custom["PL_Map_023"])
	end

	function setupPL_Map_024(player, elementID)
		setMapImage(maps_custom["PL_Map_024"])
	end

	function setupPL_Map_025(player, elementID)
		setMapImage(maps_custom["PL_Map_025"])
	end

	function setupPL_Map_026(player, elementID)
		setMapImage(maps_custom["PL_Map_026"])
	end

	function setupPL_Map_027(player, elementID)
		setMapImage(maps_custom["PL_Map_027"])
	end

	function setupPL_Map_028(player, elementID)
		setMapImage(maps_custom["PL_Map_028"])
	end

	function setupPL_Map_029(player, elementID)
		setMapImage(maps_custom["PL_Map_029"])
	end

	function setupPL_Map_030(player, elementID)
		setMapImage(maps_custom["PL_Map_030"])
	end

	function setupPL_Map_031(player, elementID)
		setMapImage(maps_custom["PL_Map_031"])
	end

	function setupPL_Map_032(player, elementID)
		setMapImage(maps_custom["PL_Map_032"])
	end

	function setupPL_Map_033(player, elementID)
		setMapImage(maps_custom["PL_Map_033"])
	end

	function setupPL_Map_034(player, elementID)
		setMapImage(maps_custom["PL_Map_034"])
	end

	function setupPL_Map_035(player, elementID)
		setMapImage(maps_custom["PL_Map_035"])
	end

	function setupPL_Map_036(player, elementID)
		setMapImage(maps_custom["PL_Map_036"])
	end

	function setupPL_Map_037(player, elementID)
		setMapImage(maps_custom["PL_Map_037"])
	end

	function setupPL_Map_038(player, elementID)
		setMapImage(maps_custom["PL_Map_038"])
	end

	function setupPL_Map_039(player, elementID)
		setMapImage(maps_custom["PL_Map_039"])
	end

	function setupPL_Map_040(player, elementID)
		setMapImage(maps_custom["PL_Map_040"])
	end

	function setupPL_Map_041(player, elementID)
		setMapImage(maps_custom["PL_Map_041"])
	end

	function setupPL_Map_042(player, elementID)
		setMapImage(maps_custom["PL_Map_042"])
	end

	function setupPL_Map_043(player, elementID)
		setMapImage(maps_custom["PL_Map_043"])
	end

	function setupPL_Map_044(player, elementID)
		setMapImage(maps_custom["PL_Map_044"])
	end

	function setupPL_Map_045(player, elementID)
		setMapImage(maps_custom["PL_Map_045"])
	end

	function setupPL_Map_046(player, elementID)
		setMapImage(maps_custom["PL_Map_046"])
	end

	function setupPL_Map_047(player, elementID)
		setMapImage(maps_custom["PL_Map_047"])
	end

	function setupPL_Map_048(player, elementID)
		setMapImage(maps_custom["PL_Map_048"])
	end

	function setupPL_Map_049(player, elementID)
		setMapImage(maps_custom["PL_Map_049"])
	end

	function setupPL_Map_050(player, elementID)
		setMapImage(maps_custom["PL_Map_050"])
	end

	function setupPL_Map_051(player, elementID)
		setMapImage(maps_custom["PL_Map_051"])
	end

	function setupPL_Map_052(player, elementID)
		setMapImage(maps_custom["PL_Map_052"])
	end

	function setupPL_Map_053(player, elementID)
		setMapImage(maps_custom["PL_Map_053"])
	end

	function setupPL_Map_054(player, elementID)
		setMapImage(maps_custom["PL_Map_054"])
	end

	function setupPL_Map_055(player, elementID)
		setMapImage(maps_custom["PL_Map_055"])
	end

	function setupPL_Map_056(player, elementID)
		setMapImage(maps_custom["PL_Map_056"])
	end

	function setupPL_Map_057(player, elementID)
		setMapImage(maps_custom["PL_Map_057"])
	end

	function setupPL_Map_058(player, elementID)
		setMapImage(maps_custom["PL_Map_058"])
	end

	function setupPL_Map_059(player, elementID)
		setMapImage(maps_custom["PL_Map_059"])
	end

	function setupPL_Map_060(player, elementID)
		setMapImage(maps_custom["PL_Map_060"])
	end

	function setupPL_Map_061(player, elementID)
		setMapImage(maps_custom["PL_Map_061"])
	end

	function setupPL_Map_062(player, elementID)
		setMapImage(maps_custom["PL_Map_062"])
	end

	function setupPL_Map_063(player, elementID)
		setMapImage(maps_custom["PL_Map_063"])
	end

	function setupPL_Map_064(player, elementID)
		setMapImage(maps_custom["PL_Map_064"])
	end

	function setupPL_Map_065(player, elementID)
		setMapImage(maps_custom["PL_Map_065"])
	end

	function setupPL_Map_066(player, elementID)
		setMapImage(maps_custom["PL_Map_066"])
	end

	function setupPL_Map_067(player, elementID)
		setMapImage(maps_custom["PL_Map_067"])
	end

	function setupPL_Map_068(player, elementID)
		setMapImage(maps_custom["PL_Map_068"])
	end

	function setupPL_Map_069(player, elementID)
		setMapImage(maps_custom["PL_Map_069"])
	end

	function setupPL_Map_070(player, elementID)
		setMapImage(maps_custom["PL_Map_070"])
	end

	function setupPL_Map_071(player, elementID)
		setMapImage(maps_custom["PL_Map_071"])
	end

	function setupPL_Map_072(player, elementID)
		setMapImage(maps_custom["PL_Map_072"])
	end

	function setupPL_Map_073(player, elementID)
		setMapImage(maps_custom["PL_Map_073"])
	end

	function setupPL_Map_074(player, elementID)
		setMapImage(maps_custom["PL_Map_074"])
	end

	function setupPL_Map_075(player, elementID)
		setMapImage(maps_custom["PL_Map_075"])
	end

	function setupPL_Map_076(player, elementID)
		setMapImage(maps_custom["PL_Map_076"])
	end

	function setupPL_Map_077(player, elementID)
		setMapImage(maps_custom["PL_Map_077"])
	end

	function setupPL_Map_078(player, elementID)
		setMapImage(maps_custom["PL_Map_078"])
	end

	function setupPL_Map_079(player, elementID)
		setMapImage(maps_custom["PL_Map_079"])
	end

	function setupPL_Map_080(player, elementID)
		setMapImage(maps_custom["PL_Map_080"])
	end

	function setupPL_Map_081(player, elementID)
		setMapImage(maps_custom["PL_Map_081"])
	end

	function setupPL_Map_082(player, elementID)
		setMapImage(maps_custom["PL_Map_082"])
	end

	function setupPL_Map_083(player, elementID)
		setMapImage(maps_custom["PL_Map_083"])
	end

	function setupPL_Map_084(player, elementID)
		setMapImage(maps_custom["PL_Map_084"])
	end

	function setupPL_Map_085(player, elementID)
		setMapImage(maps_custom["PL_Map_085"])
	end

	function setupPL_Map_086(player, elementID)
		setMapImage(maps_custom["PL_Map_086"])
	end

	function setupPL_Map_087(player, elementID)
		setMapImage(maps_custom["PL_Map_087"])
	end

	function setupPL_Map_088(player, elementID)
		setMapImage(maps_custom["PL_Map_088"])
	end

	function setupPL_Map_089(player, elementID)
		setMapImage(maps_custom["PL_Map_089"])
	end

	function setupPL_Map_090(player, elementID)
		setMapImage(maps_custom["PL_Map_090"])
	end

	function setupPL_Map_091(player, elementID)
		setMapImage(maps_custom["PL_Map_091"])
	end

	function setupPL_Map_092(player, elementID)
		setMapImage(maps_custom["PL_Map_092"])
	end

	function setupPL_Map_093(player, elementID)
		setMapImage(maps_custom["PL_Map_093"])
	end

	function setupPL_Map_094(player, elementID)
		setMapImage(maps_custom["PL_Map_094"])
	end

	function setupPL_Map_095(player, elementID)
		setMapImage(maps_custom["PL_Map_095"])
	end

	function setupPL_Map_096(player, elementID)
		setMapImage(maps_custom["PL_Map_096"])
	end

	function setupPL_Map_097(player, elementID)
		setMapImage(maps_custom["PL_Map_097"])
	end

	function setupPL_Map_098(player, elementID)
		setMapImage(maps_custom["PL_Map_098"])
	end

	function setupPL_Map_099(player, elementID)
		setMapImage(maps_custom["PL_Map_099"])
	end

	function setupPL_Map_100(player, elementID)
		setMapImage(maps_custom["PL_Map_100"])
	end

	function setupPL_Map_101(player, elementID)
		setMapImage(maps_custom["PL_Map_101"])
	end

	function setupPL_Map_102(player, elementID)
		setMapImage(maps_custom["PL_Map_102"])
	end

	function setupPL_Map_103(player, elementID)
		setMapImage(maps_custom["PL_Map_103"])
	end

	function setupPL_Map_104(player, elementID)
		setMapImage(maps_custom["PL_Map_104"])
	end

	function setupPL_Map_105(player, elementID)
		setMapImage(maps_custom["PL_Map_105"])
	end

	function setupPL_Map_106(player, elementID)
		setMapImage(maps_custom["PL_Map_106"])
	end

	function setupPL_Map_107(player, elementID)
		setMapImage(maps_custom["PL_Map_107"])
	end

	function setupPL_Map_108(player, elementID)
		setMapImage(maps_custom["PL_Map_108"])
	end

	function setupPL_Map_109(player, elementID)
		setMapImage(maps_custom["PL_Map_109"])
	end

	function setupPL_Map_110(player, elementID)
		setMapImage(maps_custom["PL_Map_110"])
	end

	function setupPL_Map_111(player, elementID)
		setMapImage(maps_custom["PL_Map_111"])
	end

	function setupPL_Map_112(player, elementID)
		setMapImage(maps_custom["PL_Map_112"])
	end

	function setupPL_Map_113(player, elementID)
		setMapImage(maps_custom["PL_Map_113"])
	end

	function setupPL_Map_114(player, elementID)
		setMapImage(maps_custom["PL_Map_114"])
	end

	function setupPL_Map_115(player, elementID)
		setMapImage(maps_custom["PL_Map_115"])
	end

	function setupPL_Map_116(player, elementID)
		setMapImage(maps_custom["PL_Map_116"])
	end

	function setupPL_Map_117(player, elementID)
		setMapImage(maps_custom["PL_Map_117"])
	end

	function setupPL_Map_118(player, elementID)
		setMapImage(maps_custom["PL_Map_118"])
	end

	function setupPL_Map_119(player, elementID)
		setMapImage(maps_custom["PL_Map_119"])
	end

	function setupPL_Map_120(player, elementID)
		setMapImage(maps_custom["PL_Map_120"])
	end

	function setupPL_Map_121(player, elementID)
		setMapImage(maps_custom["PL_Map_121"])
	end

	function setupPL_Map_122(player, elementID)
		setMapImage(maps_custom["PL_Map_122"])
	end

	function setupPL_Map_123(player, elementID)
		setMapImage(maps_custom["PL_Map_123"])
	end

	function setupPL_Map_124(player, elementID)
		setMapImage(maps_custom["PL_Map_124"])
	end

	function setupPL_Map_125(player, elementID)
		setMapImage(maps_custom["PL_Map_125"])
	end

	function setupPL_Map_126(player, elementID)
		setMapImage(maps_custom["PL_Map_126"])
	end

	function setupPL_Map_127(player, elementID)
		setMapImage(maps_custom["PL_Map_127"])
	end

	function setupPL_Map_128(player, elementID)
		setMapImage(maps_custom["PL_Map_128"])
	end

	function setupPL_Map_129(player, elementID)
		setMapImage(maps_custom["PL_Map_129"])
	end

	function setupPL_Map_130(player, elementID)
		setMapImage(maps_custom["PL_Map_130"])
	end

	function setupPL_Map_131(player, elementID)
		setMapImage(maps_custom["PL_Map_131"])
	end

	function setupPL_Map_132(player, elementID)
		setMapImage(maps_custom["PL_Map_132"])
	end

	function setupPL_Map_133(player, elementID)
		setMapImage(maps_custom["PL_Map_133"])
	end

	function setupPL_Map_134(player, elementID)
		setMapImage(maps_custom["PL_Map_134"])
	end

	function setupPL_Map_135(player, elementID)
		setMapImage(maps_custom["PL_Map_135"])
	end

	function setupPL_Map_136(player, elementID)
		setMapImage(maps_custom["PL_Map_136"])
	end

	function setupPL_Map_137(player, elementID)
		setMapImage(maps_custom["PL_Map_137"])
	end

	function setupPL_Map_138(player, elementID)
		setMapImage(maps_custom["PL_Map_138"])
	end

	function setupPL_Map_139(player, elementID)
		setMapImage(maps_custom["PL_Map_139"])
	end

	function setupPL_Map_140(player, elementID)
		setMapImage(maps_custom["PL_Map_140"])
	end

	function setupPL_Map_141(player, elementID)
		setMapImage(maps_custom["PL_Map_141"])
	end

	function setupPL_Map_142(player, elementID)
		setMapImage(maps_custom["PL_Map_142"])
	end

	function setupPL_Map_143(player, elementID)
		setMapImage(maps_custom["PL_Map_143"])
	end

	function setupPL_Map_144(player, elementID)
		setMapImage(maps_custom["PL_Map_144"])
	end

	function setupPL_Map_145(player, elementID)
		setMapImage(maps_custom["PL_Map_145"])
	end

	function setupPL_Map_146(player, elementID)
		setMapImage(maps_custom["PL_Map_146"])
	end

	function setupPL_Map_147(player, elementID)
		setMapImage(maps_custom["PL_Map_147"])
	end

	function setupPL_Map_148(player, elementID)
		setMapImage(maps_custom["PL_Map_148"])
	end

	function setupPL_Map_149(player, elementID)
		setMapImage(maps_custom["PL_Map_149"])
	end

	function setupPL_Map_150(player, elementID)
		setMapImage(maps_custom["PL_Map_150"])
	end

	function setupPL_Map_151(player, elementID)
		setMapImage(maps_custom["PL_Map_151"])
	end

	function setupPL_Map_152(player, elementID)
		setMapImage(maps_custom["PL_Map_152"])
	end

	function setupPL_Map_153(player, elementID)
		setMapImage(maps_custom["PL_Map_153"])
	end

	function setupPL_Map_154(player, elementID)
		setMapImage(maps_custom["PL_Map_154"])
	end

	function setupPL_Map_155(player, elementID)
		setMapImage(maps_custom["PL_Map_155"])
	end

	function setupPL_Map_156(player, elementID)
		setMapImage(maps_custom["PL_Map_156"])
	end

	function setupPL_Map_157(player, elementID)
		setMapImage(maps_custom["PL_Map_157"])
	end

	function setupPL_Map_158(player, elementID)
		setMapImage(maps_custom["PL_Map_158"])
	end

	function setupPL_Map_159(player, elementID)
		setMapImage(maps_custom["PL_Map_159"])
	end

	function setupPL_Map_160(player, elementID)
		setMapImage(maps_custom["PL_Map_160"])
	end

	function setupPL_Map_161(player, elementID)
		setMapImage(maps_custom["PL_Map_161"])
	end

	function setupPL_Map_162(player, elementID)
		setMapImage(maps_custom["PL_Map_162"])
	end

	function setupPL_Map_163(player, elementID)
		setMapImage(maps_custom["PL_Map_163"])
	end

	function setupPL_Map_164(player, elementID)
		setMapImage(maps_custom["PL_Map_164"])
	end

	function setupPL_Map_165(player, elementID)
		setMapImage(maps_custom["PL_Map_165"])
	end

	function setupPL_Map_166(player, elementID)
		setMapImage(maps_custom["PL_Map_166"])
	end

	function setupPL_Map_167(player, elementID)
		setMapImage(maps_custom["PL_Map_167"])
	end

	function setupPL_Map_168(player, elementID)
		setMapImage(maps_custom["PL_Map_168"])
	end

	function setupPL_Map_169(player, elementID)
		setMapImage(maps_custom["PL_Map_169"])
	end

	function setupPL_Map_170(player, elementID)
		setMapImage(maps_custom["PL_Map_170"])
	end

	function setupPL_Map_171(player, elementID)
		setMapImage(maps_custom["PL_Map_171"])
	end

	function setupPL_Map_172(player, elementID)
		setMapImage(maps_custom["PL_Map_172"])
	end

	function setupPL_Map_173(player, elementID)
		setMapImage(maps_custom["PL_Map_173"])
	end

	function setupPL_Map_174(player, elementID)
		setMapImage(maps_custom["PL_Map_174"])
	end

	function setupPL_Map_175(player, elementID)
		setMapImage(maps_custom["PL_Map_175"])
	end

	function setupPL_Map_176(player, elementID)
		setMapImage(maps_custom["PL_Map_176"])
	end

	function setupPL_Map_177(player, elementID)
		setMapImage(maps_custom["PL_Map_177"])
	end

	function setupPL_Map_178(player, elementID)
		setMapImage(maps_custom["PL_Map_178"])
	end

	function setupPL_Map_179(player, elementID)
		setMapImage(maps_custom["PL_Map_179"])
	end

	function setupPL_Map_180(player, elementID)
		setMapImage(maps_custom["PL_Map_180"])
	end

	function setupPL_Map_181(player, elementID)
		setMapImage(maps_custom["PL_Map_181"])
	end

	function setupPL_Map_182(player, elementID)
		setMapImage(maps_custom["PL_Map_182"])
	end

	function setupPL_Map_183(player, elementID)
		setMapImage(maps_custom["PL_Map_183"])
	end

	function setupPL_Map_184(player, elementID)
		setMapImage(maps_custom["PL_Map_184"])
	end

	function setupPL_Map_185(player, elementID)
		setMapImage(maps_custom["PL_Map_185"])
	end

	function setupPL_Map_186(player, elementID)
		setMapImage(maps_custom["PL_Map_186"])
	end

	function setupPL_Map_187(player, elementID)
		setMapImage(maps_custom["PL_Map_187"])
	end

	function setupPL_Map_188(player, elementID)
		setMapImage(maps_custom["PL_Map_188"])
	end

	function setupPL_Map_189(player, elementID)
		setMapImage(maps_custom["PL_Map_189"])
	end

	function setupPL_Map_190(player, elementID)
		setMapImage(maps_custom["PL_Map_190"])
	end

	function setupPL_Map_191(player, elementID)
		setMapImage(maps_custom["PL_Map_191"])
	end

	function setupPL_Map_192(player, elementID)
		setMapImage(maps_custom["PL_Map_192"])
	end

	function setupPL_Map_193(player, elementID)
		setMapImage(maps_custom["PL_Map_193"])
	end

	function setupPL_Map_194(player, elementID)
		setMapImage(maps_custom["PL_Map_194"])
	end

	function setupPL_Map_195(player, elementID)
		setMapImage(maps_custom["PL_Map_195"])
	end

	function setupPL_Map_196(player, elementID)
		setMapImage(maps_custom["PL_Map_196"])
	end

	function setupPL_Map_197(player, elementID)
		setMapImage(maps_custom["PL_Map_197"])
	end

	function setupPL_Map_198(player, elementID)
		setMapImage(maps_custom["PL_Map_198"])
	end

	function setupPL_Map_199(player, elementID)
		setMapImage(maps_custom["PL_Map_199"])
	end

	function setupPL_Map_200(player, elementID)
		setMapImage(maps_custom["PL_Map_200"])
	end

	function setupPL_Map_201(player, elementID)
		setMapImage(maps_custom["PL_Map_201"])
	end

	function setupPL_Map_202(player, elementID)
		setMapImage(maps_custom["PL_Map_202"])
	end

	function setupPL_Map_203(player, elementID)
		setMapImage(maps_custom["PL_Map_203"])
	end

	function setupPL_Map_204(player, elementID)
		setMapImage(maps_custom["PL_Map_204"])
	end

	function setupPL_Map_205(player, elementID)
		setMapImage(maps_custom["PL_Map_205"])
	end

	function setupPL_Map_206(player, elementID)
		setMapImage(maps_custom["PL_Map_206"])
	end

	function setupPL_Map_207(player, elementID)
		setMapImage(maps_custom["PL_Map_207"])
	end

	function setupPL_Map_208(player, elementID)
		setMapImage(maps_custom["PL_Map_208"])
	end

	function setupPL_Map_209(player, elementID)
		setMapImage(maps_custom["PL_Map_209"])
	end

	function setupPL_Map_210(player, elementID)
		setMapImage(maps_custom["PL_Map_210"])
	end

	function setupPL_Map_211(player, elementID)
		setMapImage(maps_custom["PL_Map_211"])
	end

	function setupPL_Map_212(player, elementID)
		setMapImage(maps_custom["PL_Map_212"])
	end

	function setupPL_Map_213(player, elementID)
		setMapImage(maps_custom["PL_Map_213"])
	end

	function setupPL_Map_214(player, elementID)
		setMapImage(maps_custom["PL_Map_214"])
	end

	function setupPL_Map_215(player, elementID)
		setMapImage(maps_custom["PL_Map_215"])
	end

	function setupPL_Map_216(player, elementID)
		setMapImage(maps_custom["PL_Map_216"])
	end

	function setupPL_Map_217(player, elementID)
		setMapImage(maps_custom["PL_Map_217"])
	end

	function setupPL_Map_218(player, elementID)
		setMapImage(maps_custom["PL_Map_218"])
	end

	function setupPL_Map_219(player, elementID)
		setMapImage(maps_custom["PL_Map_219"])
	end

	function setupPL_Map_220(player, elementID)
		setMapImage(maps_custom["PL_Map_220"])
	end

	function setupPL_Map_221(player, elementID)
		setMapImage(maps_custom["PL_Map_221"])
	end

	function setupPL_Map_222(player, elementID)
		setMapImage(maps_custom["PL_Map_222"])
	end



end

function setMapImage(url)
    
    mapTile = getObjectFromGUID(mapTileGUID)

    mapTileObj = mapTile.getCustomObject()
    mapTileObj.image = url
    mapTileObj.secondary_image = url
    
    mapTile.setCustomObject(mapTileObj)

    mapTile.reload()

    --returnToMenu()
end

function returnToMenu(player, elementID)
    self.UI.setAttribute("menuButtonPanel", "active", true)
    	self.UI.setAttribute("mapSelectionFD", "active", false)
    	self.UI.setAttribute("mapSelectionFDe", "active", false)
    	self.UI.setAttribute("mapSelectionCustom", "active", false)
end

function openMapSelectionFD(player, elementID)
    self.UI.setAttribute("menuButtonPanel", "active", false)
    	self.UI.setAttribute("mapSelectionFD", "active", true)
    	self.UI.setAttribute("mapSelectionFDe", "active", false)
    	self.UI.setAttribute("mapSelectionCustom", "active", false)
end

function openMapSelectionFDe(player, elementID)
    self.UI.setAttribute("menuButtonPanel", "active", false)
    	self.UI.setAttribute("mapSelectionFD", "active", false)
    	self.UI.setAttribute("mapSelectionFDe", "active", true)
    	self.UI.setAttribute("mapSelectionCustom", "active", false)
end

function openMapSelectionCustom(player, elementID)
    self.UI.setAttribute("menuButtonPanel", "active", false)
    	self.UI.setAttribute("mapSelectionFD", "active", false)
    	self.UI.setAttribute("mapSelectionFDe", "active", false)
    	self.UI.setAttribute("mapSelectionCustom", "active", true)
end

function toggleHideSetup()
    local sp = Global.getVar("setup_packed")

    if(sp) then
        memoryBagSetup.call('buttonClick_place',{})
    else
        memoryBagSetup.call('buttonClick_recall',{})
    end
end

function hideModMenu()
    Global.setVar("mod_packed", true)
    memoryBagModMenu.call('buttonClick_recall',{})
    UI.setAttribute("showModMenuButton", "active", true)

end