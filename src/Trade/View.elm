module Trade.View exposing (root)

import Array
import BigInt exposing (BigInt)
import CommonTypes exposing (..)
import Contracts.Types as CTypes exposing (FullTradeInfo)
import Element exposing (Attribute, Element)
import Element.Background
import Element.Border
import Element.Events
import Element.Font
import Element.Input
import ElementHelpers as EH
import Eth.Utils
import FiatValue exposing (FiatValue)
import Images exposing (Image)
import Margin
import Network exposing (..)
import PaymentMethods exposing (PaymentMethod)
import Time
import TimeHelpers
import TokenValue exposing (TokenValue)
import Trade.ChatHistory.View as ChatHistory
import Trade.Types exposing (..)


root : Time.Posix -> Model -> Element.Element Msg
root time model =
    case model.trade of
        CTypes.LoadedTrade tradeInfo ->
            Element.column
                [ Element.width Element.fill
                , Element.height Element.fill
                , Element.spacing 40
                , Element.inFront <| chatOverlayElement model
                , Element.inFront <| getModalOrNone model
                ]
                [ header tradeInfo model.stats model.userInfo model.ethNode.network
                , Element.column
                    [ Element.width Element.fill
                    , Element.paddingXY 40 0
                    , Element.spacing 40
                    ]
                    [ phasesElement tradeInfo model.expandedPhase model.userInfo time
                    , PaymentMethods.viewList tradeInfo.paymentMethods Nothing
                    ]
                ]

        CTypes.PartiallyLoadedTrade partialTradeInfo ->
            Element.el
                [ Element.centerX
                , Element.centerY
                , Element.Font.size 30
                ]
                (Element.text "Loading contract info...")


header : FullTradeInfo -> StatsModel -> Maybe UserInfo -> Network -> Element Msg
header trade stats maybeUserInfo network =
    EH.niceFloatingRow
        [ tradeStatusElement trade network
        , daiAmountElement trade maybeUserInfo
        , fiatElement trade
        , marginElement trade maybeUserInfo
        , statsElement stats
        , case maybeUserInfo of
            Just userInfo ->
                actionButtonsElement trade userInfo

            Nothing ->
                Element.none
        ]


tradeStatusElement : FullTradeInfo -> Network -> Element Msg
tradeStatusElement trade network =
    EH.withHeader
        "Trade Status"
        (Element.column
            [ Element.Font.size 24
            , Element.Font.medium
            , Element.spacing 8
            ]
            [ Element.text
                (case trade.state.phase of
                    CTypes.Open ->
                        case trade.parameters.openMode of
                            CTypes.BuyerOpened ->
                                "Open Buy Offer"

                            CTypes.SellerOpened ->
                                "Open Sell Offer"

                    CTypes.Committed ->
                        "Committed"

                    CTypes.Claimed ->
                        "Claimed"

                    CTypes.Closed ->
                        "Closed"
                )
            , EH.etherscanAddressLink
                [ Element.Font.size 12
                , Element.Font.color EH.blue
                , Element.Font.underline
                ]
                network
                trade.creationInfo.address
            ]
        )


daiAmountElement : FullTradeInfo -> Maybe UserInfo -> Element Msg
daiAmountElement trade maybeUserInfo =
    let
        maybeInitiatorOrResponder =
            Maybe.andThen
                (CTypes.getInitiatorOrResponder trade)
                (Maybe.map .address maybeUserInfo)
    in
    EH.withHeader
        (case ( trade.parameters.openMode, maybeInitiatorOrResponder ) of
            ( CTypes.BuyerOpened, Just Initiator ) ->
                "You're Buying"

            ( CTypes.BuyerOpened, _ ) ->
                "Buying"

            ( CTypes.SellerOpened, Just Initiator ) ->
                "You're Selling"

            ( CTypes.SellerOpened, _ ) ->
                "Selling"
        )
        (renderDaiAmount trade.parameters.tradeAmount)


renderDaiAmount : TokenValue -> Element Msg
renderDaiAmount daiAmount =
    Element.row
        [ Element.spacing 8 ]
        [ Images.toElement [] Images.daiSymbol
        , Element.el
            [ Element.Font.size 24
            , Element.Font.medium
            ]
            (Element.text <| TokenValue.toConciseString daiAmount)
        ]


fiatElement : FullTradeInfo -> Element Msg
fiatElement trade =
    EH.withHeader
        "For Fiat"
        (renderFiatAmount trade.parameters.fiatPrice)


renderFiatAmount : FiatValue -> Element Msg
renderFiatAmount fiatValue =
    Element.row
        [ Element.spacing 5 ]
        [ FiatValue.typeStringToSymbol fiatValue.fiatType
        , Element.el
            [ Element.Font.size 24
            , Element.Font.medium
            ]
            (Element.text <| FiatValue.renderToStringFull fiatValue)
        ]


marginElement : FullTradeInfo -> Maybe UserInfo -> Element Msg
marginElement trade maybeUserInfo =
    EH.withHeader
        "At Margin"
        (case trade.derived.margin of
            Just marginFloat ->
                renderMargin marginFloat maybeUserInfo

            Nothing ->
                EH.comingSoonMsg [] "Margin for non-USD currencies coming soon!"
        )


renderMargin : Float -> Maybe UserInfo -> Element Msg
renderMargin marginFloat maybeUserInfo =
    let
        marginString =
            Margin.marginToString marginFloat ++ "%"

        image =
            if marginFloat == 0 then
                Images.none

            else
                Images.marginSymbol (marginFloat > 0) Nothing
    in
    Element.row [ Element.spacing 5 ]
        [ Element.text marginString
        , Images.toElement [] image
        ]


statsElement : StatsModel -> Element Msg
statsElement stats =
    EH.withHeader
        "Initiator Stats"
        (EH.comingSoonMsg [] "Stats coming soon!")


actionButtonsElement : FullTradeInfo -> UserInfo -> Element Msg
actionButtonsElement trade userInfo =
    Element.row
        [ Element.spacing 8 ]
        (case
            ( trade.state.phase
            , CTypes.getInitiatorOrResponder trade userInfo.address
            , CTypes.getBuyerOrSeller trade userInfo.address
            )
         of
            ( CTypes.Open, Just Initiator, _ ) ->
                [ Element.map StartContractAction <| EH.blueButton "Remove and Refund this Trade" Recall ]

            ( CTypes.Open, Nothing, _ ) ->
                let
                    depositAmount =
                        CTypes.responderDeposit trade.parameters
                            |> TokenValue.getBigInt
                in
                [ EH.redButton "Deposit and Commit to Trade" <| CommitClicked trade userInfo depositAmount ]

            ( CTypes.Committed, _, Just Buyer ) ->
                [ Element.map StartContractAction <| EH.orangeButton "Abort Trade" Abort
                , Element.map StartContractAction <| EH.redButton "Confirm Payment" Claim
                ]

            ( CTypes.Claimed, _, Just Seller ) ->
                [ Element.map StartContractAction <| EH.redButton "Burn it all" Burn
                , Element.map StartContractAction <| EH.blueButton "Release Everything Now" Release
                ]

            _ ->
                []
        )


phasesElement : FullTradeInfo -> CTypes.Phase -> Maybe UserInfo -> Time.Posix -> Element Msg
phasesElement trade expandedPhase maybeUserInfo currentTime =
    Element.row
        [ Element.width Element.fill
        , Element.height Element.shrink
        , Element.spacing 20
        ]
    <|
        case trade.state.phase of
            CTypes.Closed ->
                [ Element.el
                    (commonPhaseAttributes
                        ++ [ Element.width Element.fill
                           , Element.Background.color EH.activePhaseBackgroundColor
                           ]
                    )
                    (Element.el
                        [ Element.centerX
                        , Element.centerY
                        , Element.Font.size 20
                        , Element.Font.semiBold
                        , Element.Font.color EH.white
                        ]
                        (Element.text "Trade Closed")
                    )
                ]

            _ ->
                [ phaseElement CTypes.Open trade maybeUserInfo (expandedPhase == CTypes.Open) currentTime
                , phaseElement CTypes.Committed trade maybeUserInfo (expandedPhase == CTypes.Committed) currentTime
                , phaseElement CTypes.Claimed trade maybeUserInfo (expandedPhase == CTypes.Claimed) currentTime
                ]


activePhaseAttributes =
    [ Element.Background.color EH.activePhaseBackgroundColor
    , Element.Font.color EH.white
    ]


inactivePhaseAttributes =
    [ Element.Background.color EH.white
    ]


commonPhaseAttributes =
    [ Element.Border.rounded 12
    , Element.height (Element.shrink |> Element.minimum 360)
    ]


phaseElement : CTypes.Phase -> FullTradeInfo -> Maybe UserInfo -> Bool -> Time.Posix -> Element Msg
phaseElement viewPhase trade maybeUserInfo expanded currentTime =
    let
        ( viewPhaseInt, activePhaseInt ) =
            ( CTypes.phaseToInt viewPhase
            , CTypes.phaseToInt trade.state.phase
            )

        viewPhaseState =
            if viewPhaseInt > activePhaseInt then
                NotStarted

            else if viewPhaseInt == activePhaseInt then
                Active

            else
                Finished

        fullInterval =
            case viewPhase of
                CTypes.Open ->
                    trade.parameters.autorecallInterval

                CTypes.Committed ->
                    trade.parameters.autoabortInterval

                CTypes.Claimed ->
                    trade.parameters.autoreleaseInterval

                _ ->
                    Time.millisToPosix 0

        displayInterval =
            case viewPhaseState of
                NotStarted ->
                    fullInterval

                Active ->
                    TimeHelpers.sub
                        (TimeHelpers.add trade.state.phaseStartTime fullInterval)
                        currentTime

                Finished ->
                    Time.millisToPosix 0

        titleElement =
            case viewPhase of
                CTypes.Open ->
                    "Open Window"

                CTypes.Committed ->
                    "Payment Window"

                CTypes.Claimed ->
                    "Release Window"

                CTypes.Closed ->
                    "Closed"

        firstEl =
            phaseStatusElement
                Images.none
                titleElement
                displayInterval
                viewPhaseState

        secondEl =
            Element.el
                [ Element.padding 30
                , Element.width Element.fill
                , Element.height Element.fill
                ]
                (phaseAdviceElement viewPhase trade maybeUserInfo)

        borderEl =
            Element.el
                [ Element.height Element.fill
                , Element.width <| Element.px 1
                , Element.Background.color <|
                    case viewPhaseState of
                        Active ->
                            Element.rgb 0 0 1

                        _ ->
                            EH.lightGray
                ]
                Element.none
    in
    if expanded then
        Element.row
            (commonPhaseAttributes
                ++ (if viewPhaseState == Active then
                        activePhaseAttributes

                    else
                        inactivePhaseAttributes
                   )
                ++ [ Element.width Element.fill ]
            )
            [ firstEl, borderEl, secondEl ]

    else
        Element.row
            (commonPhaseAttributes
                ++ (if viewPhaseState == Active then
                        activePhaseAttributes

                    else
                        inactivePhaseAttributes
                   )
                ++ [ Element.pointer
                   , Element.Events.onClick <| ExpandPhase viewPhase
                   ]
            )
            [ firstEl ]


phaseStatusElement : Image -> String -> Time.Posix -> PhaseState -> Element Msg
phaseStatusElement icon title interval phaseState =
    let
        titleColor =
            case phaseState of
                Active ->
                    Element.rgb255 0 226 255

                _ ->
                    EH.black

        titleElement =
            Element.el
                [ Element.Font.color titleColor
                , Element.Font.size 20
                , Element.Font.semiBold
                , Element.centerX
                ]
                (Element.text title)

        intervalElement =
            Element.el [ Element.centerX ]
                (EH.interval False Nothing interval)

        phaseStateElement =
            Element.el
                [ Element.centerX
                , Element.Font.italic
                , Element.Font.semiBold
                , Element.Font.size 16
                ]
                (Element.text <| phaseStateString phaseState)
    in
    Element.el
        [ Element.height <| Element.px 360
        , Element.width <| Element.px 270
        , Element.padding 30
        ]
    <|
        Element.column
            [ Element.centerX
            , Element.height Element.fill
            , Element.spaceEvenly
            ]
            [ Element.none -- add icon!
            , titleElement
            , intervalElement
            , phaseStateElement
            ]


phaseStateString : PhaseState -> String
phaseStateString status =
    case status of
        NotStarted ->
            "Not Started"

        Active ->
            "Active"

        Finished ->
            "Finished"


phaseAdviceElement : CTypes.Phase -> CTypes.FullTradeInfo -> Maybe UserInfo -> Element Msg
phaseAdviceElement viewPhase trade maybeUserInfo =
    let
        phaseIsActive =
            viewPhase == trade.state.phase

        maybeBuyerOrSeller =
            maybeUserInfo
                |> Maybe.map .address
                |> Maybe.andThen (CTypes.getBuyerOrSeller trade)

        mainFontColor =
            if phaseIsActive then
                EH.white

            else
                EH.black

        makeParagraph =
            Element.paragraph
                [ Element.Font.color mainFontColor
                , Element.Font.size 18
                , Element.Font.semiBold
                ]

        emphasizedColor =
            if phaseIsActive then
                Element.rgb255 0 226 255

            else
                Element.rgb255 16 7 234

        emphasizedText =
            Element.el [ Element.Font.color emphasizedColor ] << Element.text

        scaryText =
            Element.el [ Element.Font.color <| Element.rgb 1 0 0 ] << Element.text

        tradeAmountString =
            TokenValue.toConciseString trade.parameters.tradeAmount ++ " DAI"

        fiatAmountString =
            FiatValue.renderToStringFull trade.parameters.fiatPrice

        buyerDepositString =
            TokenValue.toConciseString trade.parameters.buyerDeposit ++ " DAI"

        tradePlusDepositString =
            (TokenValue.add
                trade.parameters.tradeAmount
                trade.parameters.buyerDeposit
                |> TokenValue.toConciseString
            )
                ++ " DAI"

        abortPunishment =
            TokenValue.div
                trade.parameters.buyerDeposit
                (TokenValue.tokenValue tokenDecimals <| BigInt.fromInt 4)

        abortPunishmentString =
            TokenValue.toConciseString
                abortPunishment
                ++ " DAI"

        sellerAbortRefundString =
            TokenValue.toConciseString
                (TokenValue.sub
                    trade.parameters.tradeAmount
                    abortPunishment
                )
                ++ " DAI"

        buyerAbortRefundString =
            TokenValue.toConciseString
                (TokenValue.sub
                    trade.parameters.buyerDeposit
                    abortPunishment
                )
                ++ " DAI"

        threeFlames =
            Element.row []
                (List.repeat 3 (Images.toElement [ Element.height <| Element.px 18 ] Images.flame))

        ( titleString, paragraphEls ) =
            case ( viewPhase, maybeBuyerOrSeller ) of
                ( CTypes.Open, Nothing ) ->
                    ( "Get it while it's hot"
                    , case trade.parameters.openMode of
                        CTypes.SellerOpened ->
                            List.map makeParagraph
                                [ [ Element.text "The Seller has deposited "
                                  , emphasizedText tradeAmountString
                                  , Element.text " into this contract, and offers sell it for "
                                  , emphasizedText fiatAmountString
                                  , Element.text ". To become the Buyer, you must deposit 1/3 of the trade amount "
                                  , emphasizedText <| "(" ++ buyerDepositString ++ ")"
                                  , Element.text " into this contract by clicking \"Deposit and Commit to Trade\"."
                                  ]
                                , [ Element.text "If the trade is successful, the combined DAI balance "
                                  , emphasizedText <| "(" ++ tradePlusDepositString ++ ")"
                                  , Element.text " will be released to you. If anything goes wrong, there are "
                                  , scaryText "burable punishments "
                                  , threeFlames
                                  , Element.text " for both parties."
                                  ]
                                , [ Element.text "Don't commit unless you can fulfil one of the seller’s accepted payment methods below for "
                                  , emphasizedText fiatAmountString
                                  , Element.text " within the payment window."
                                  ]
                                ]

                        CTypes.BuyerOpened ->
                            List.map makeParagraph
                                [ [ Element.text "The Buyer is offering to buy "
                                  , emphasizedText tradeAmountString
                                  , Element.text " for "
                                  , emphasizedText fiatAmountString
                                  , Element.text ", and has deposited "
                                  , emphasizedText buyerDepositString
                                  , Element.text " into this contract as a "
                                  , scaryText "burnable bond"
                                  , Element.text ". To become the Seller, deposit "
                                  , emphasizedText tradeAmountString
                                  , Element.text " into this contract by clicking \"Deposit and Commit to Trade\"."
                                  ]
                                , [ Element.text "When you receive the "
                                  , emphasizedText fiatAmountString
                                  , Element.text " from the Buyer, the combined DAI balance "
                                  , emphasizedText <| "(" ++ tradePlusDepositString ++ ")"
                                  , Element.text " will be released to the Buyer. If anything goes wrong, there are "
                                  , scaryText "burnable punishments "
                                  , threeFlames
                                  , Element.text " for both parties."
                                  ]
                                , [ Element.text "Don't commit unless you can receive "
                                  , emphasizedText fiatAmountString
                                  , Element.text " via one of the Buyer's payment methods below, within the payment window."
                                  ]
                                ]
                    )

                ( CTypes.Open, Just buyerOrSeller ) ->
                    let
                        _ =
                            Debug.log "still have to write this hint" "open phase for initiator"
                    in
                    ( "Did you forget this is a beta?"
                    , [ makeParagraph [ Element.text "Very silly of you. This description has not yet been written. Sorry!" ] ]
                    )

                ( CTypes.Committed, Just Buyer ) ->
                    ( "Time to Pay Up"
                    , List.map makeParagraph
                        [ [ Element.text "You must now pay the Seller "
                          , emphasizedText fiatAmountString
                          , Element.text " via one of the accepted payment methods below, "
                          , Element.el [ Element.Font.semiBold ] <| Element.text "and click \"Confirm Payment\""
                          , Element.text " before the payment window runs out."
                          ]
                        , [ Element.text "If you do not confirm payment before this time is up, "
                          , emphasizedText abortPunishmentString
                          , Element.text " (1/4 of the "
                          , scaryText "burnable bond"
                          , Element.text " amount) will be "
                          , scaryText "burned"
                          , Element.text " from both you and the Seller, while the remainder of each party's deposit ("
                          , emphasizedText sellerAbortRefundString
                          , Element.text " for the Seller, "
                          , emphasizedText buyerAbortRefundString
                          , Element.text " for you) is refunded."
                          ]
                        ]
                    )

                ( CTypes.Claimed, Just Buyer ) ->
                    ( "Judgement"
                    , List.map makeParagraph
                        [ [ Element.text "If the Seller confirms receipt of payment, or fails to decide within the release window, the combined balance of "
                          , emphasizedText tradePlusDepositString
                          , Element.text " will be released to you."
                          ]
                        , [ Element.text "If they cannot confirm they've received payment from you, they will probably instead "
                          , scaryText "burn the contract's balance of "
                          , emphasizedText tradePlusDepositString
                          , Element.text "."
                          ]
                        , [ Element.text "These are the only options the Seller has. So, fingers crossed!"
                          ]
                        ]
                    )

                ( CTypes.Closed, Just _ ) ->
                    ( "Contract closed."
                    , [ makeParagraph [ Element.text "Check the chat log for the full history." ] ]
                    )

                ( CTypes.Closed, Nothing ) ->
                    ( "Contract closed."
                    , []
                    )

                other ->
                    let
                        _ =
                            Debug.log "still have to write this hint" other
                    in
                    ( "Did you forget this is a beta?"
                    , [ makeParagraph [ Element.text "Very silly of you! This description has not yet been written. Sorry!" ] ]
                    )
    in
    Element.column
        [ Element.width Element.fill
        , Element.height Element.fill
        , Element.paddingXY 90 10
        , Element.spacing 16
        ]
        [ Element.el
            [ Element.Font.size 24
            , Element.Font.semiBold
            , Element.Font.color emphasizedColor
            ]
            (Element.text titleString)
        , Element.column
            [ Element.width Element.fill
            , Element.centerY
            , Element.spacing 13
            , Element.paddingEach
                { right = 40
                , top = 0
                , bottom = 0
                , left = 0
                }
            ]
            paragraphEls
        ]


chatOverlayElement : Model -> Element Msg
chatOverlayElement model =
    case ( model.userInfo, model.trade ) of
        ( Just userInfo, CTypes.LoadedTrade trade ) ->
            if trade.state.phase == CTypes.Open then
                Element.none

            else if CTypes.getInitiatorOrResponder trade userInfo.address == Nothing then
                Element.none

            else
                let
                    openChatButton =
                        EH.elOnCircle
                            [ Element.pointer
                            , Element.Events.onClick ToggleChat
                            ]
                            80
                            (Element.rgb 1 1 1)
                            (Images.toElement
                                [ Element.centerX
                                , Element.centerY
                                , Element.moveRight 5
                                ]
                                Images.chatIcon
                            )

                    chatWindow =
                        Maybe.map
                            ChatHistory.window
                            model.chatHistoryModel
                            |> Maybe.withDefault Element.none
                in
                if model.showChatHistory then
                    EH.modal
                        (Element.rgba 0 0 0 0.6)
                        (Element.row
                            [ Element.height Element.fill
                            , Element.spacing 50
                            , Element.alignRight
                            ]
                            [ Element.map ChatHistoryMsg chatWindow
                            , Element.el [ Element.alignBottom ] openChatButton
                            ]
                        )

                else
                    Element.el
                        [ Element.alignRight
                        , Element.alignBottom
                        ]
                        openChatButton

        _ ->
            Element.none


getModalOrNone : Model -> Element Msg
getModalOrNone model =
    case model.txChainStatus of
        NoTx ->
            Element.none

        ConfirmingCommit trade userInfo deposit ->
            let
                depositAmountString =
                    TokenValue.tokenValue tokenDecimals deposit
                        |> TokenValue.toConciseString

                fiatPriceString =
                    FiatValue.renderToStringFull trade.parameters.fiatPrice

                daiAmountString =
                    TokenValue.toConciseString trade.parameters.tradeAmount ++ " DAI"

                ( buyerOrSellerEl, agreeToWhatTextList ) =
                    case CTypes.getResponderRole trade.parameters of
                        Buyer ->
                            ( Element.el [ Element.Font.medium, Element.Font.color EH.black ] <| Element.text "buyer"
                            , [ Element.text "pay the seller "
                              , Element.el [ Element.Font.color EH.blue ] <| Element.text fiatPriceString
                              , Element.text " in exchange for the "
                              , Element.el [ Element.Font.color EH.blue ] <| Element.text daiAmountString
                              , Element.text " held in this contract."
                              ]
                            )

                        Seller ->
                            ( Element.el [ Element.Font.medium, Element.Font.color EH.black ] <| Element.text "seller"
                            , [ Element.text "accept "
                              , Element.el [ Element.Font.color EH.blue ] <| Element.text fiatPriceString
                              , Element.text " from the buyer in exchange for the "
                              , Element.el [ Element.Font.color EH.blue ] <| Element.text daiAmountString
                              , Element.text " held in this contract."
                              ]
                            )
            in
            EH.closeableModal
                (Element.column
                    [ Element.spacing 20
                    , Element.centerX
                    , Element.height Element.fill
                    , Element.Font.center
                    ]
                    [ Element.el
                        [ Element.Font.size 26
                        , Element.Font.semiBold
                        , Element.centerX
                        , Element.centerY
                        ]
                        (Element.text "Just to Confirm...")
                    , Element.column
                        [ Element.spacing 20
                        , Element.centerX
                        , Element.centerY
                        ]
                        (List.map
                            (Element.paragraph
                                [ Element.width <| Element.px 500
                                , Element.centerX
                                , Element.Font.size 18
                                , Element.Font.medium
                                , Element.Font.color EH.permanentTextColor
                                ]
                            )
                            [ [ Element.text <| "You will deposit "
                              , Element.el [ Element.Font.color EH.blue ] <| Element.text <| depositAmountString ++ " DAI"
                              , Element.text ", thereby becoming the "
                              , buyerOrSellerEl
                              , Element.text " of this trade. By doing so, you are agreeing to "
                              ]
                                ++ agreeToWhatTextList
                            , [ Element.text <| "(This ususally requires two Metamask signatures. Your DAI will not be deposited until the second transaction has been mined.)" ]
                            ]
                        )
                    , Element.el
                        [ Element.alignBottom
                        , Element.centerX
                        ]
                        (EH.redButton "Yes, I definitely want to commit to this trade." (ConfirmCommit trade userInfo deposit))
                    ]
                )
                AbortCommit

        ApproveNeedsSig ->
            EH.txProcessModal
                [ Element.text "Waiting for user signature for the approve call."
                , Element.text "(check Metamask!)"
                , Element.text "Note that there will be a second transaction to sign after this."
                ]

        ApproveMining txHash ->
            EH.txProcessModal
                [ Element.text "Mining the initial approve transaction..."

                -- , Element.newTabLink [ Element.Font.underline, Element.Font.color EH.blue ]
                --     { url = EthHelpers.makeEtherscanTxUrl txHash
                --     , label = Element.text "See the transaction on Etherscan"
                --     }
                , Element.text "Funds will not be sent until you sign the next transaction."
                ]

        CommitNeedsSig ->
            EH.txProcessModal
                [ Element.text "Waiting for user signature for the final commit call."
                , Element.text "(check Metamask!)"
                , Element.text "This will make the deposit and commit you to the trade."
                ]

        CommitMining txHash ->
            EH.txProcessModal
                [ Element.text "Mining the final commit transaction..."

                -- , Element.newTabLink [ Element.Font.underline, Element.Font.color EH.blue ]
                --     { url = EthHelpers.makeEtherscanTxUrl txHash
                --     , label = Element.text "See the transaction on Etherscan"
                --     }
                ]

        ActionNeedsSig action ->
            EH.txProcessModal
                [ Element.text <| "Waiting for user signature for the " ++ actionName action ++ " call."
                , Element.text "(check Metamask!)"
                ]

        ActionMining action txHash ->
            Element.none

        TxError s ->
            EH.txProcessModal
                [ Element.text "Something has gone terribly wrong"
                , Element.text s
                ]


actionName : ContractAction -> String
actionName action =
    case action of
        Poke ->
            "poke"

        Recall ->
            "recall"

        Claim ->
            "claim"

        Abort ->
            "abort"

        Release ->
            "release"

        Burn ->
            "burn"
