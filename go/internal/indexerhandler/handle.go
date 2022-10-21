package indexerhandler

import (
	"encoding/json"
	"fmt"

	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
	"github.com/TERITORI/teritori-dapp/go/internal/indexerdb"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	cosmostx "github.com/cosmos/cosmos-sdk/types/tx"
	cosmosproto "github.com/cosmos/gogoproto/proto"
	"github.com/davecgh/go-spew/spew"
	"github.com/pkg/errors"
	tenderminttypes "github.com/tendermint/tendermint/rpc/core/types"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

type Message struct {
	Msg      *codectypes.Any
	MsgIndex int
	MsgID    string
	TxHash   string
	Events   EventsMap
	Log      TendermintTxLog
}

type Config struct {
	TNSContractAddress   string
	RESTEndpoint         string
	MinterCodeID         uint64
	VaultContractAddress string
	TNSDefaultImageURL   string
}

type Handler struct {
	db *gorm.DB

	logger *zap.Logger
	config Config
}

func NewHandler(db *gorm.DB, config Config, logger *zap.Logger) (*Handler, error) {
	if db == nil {
		return nil, errors.New("nil db")
	}
	if logger == nil {
		logger = zap.NewNop()
	}
	return &Handler{
		db:     db,
		logger: logger,
		config: config,
	}, nil
}

func (h *Handler) HandleTendermintResultTx(tx *tenderminttypes.ResultTx) error {
	var logs []TendermintTxLog
	if err := json.Unmarshal([]byte(tx.TxResult.Log), &logs); err != nil {
		panic(errors.Wrap(err, "failed to parse tx log"))
	}

	var cosmosTx cosmostx.Tx
	if err := cosmosproto.Unmarshal(tx.Tx, &cosmosTx); err != nil {
		return errors.Wrap(err, "failed to unmarshal tx")
	}

	return h.HandleTx(tx.Hash.String(), cosmosTx, logs)
}

func (h *Handler) HandleTx(hash string, tx cosmostx.Tx, logs []TendermintTxLog) error {
	if len(logs) != len(tx.Body.Messages) {
		return errors.New("messages and results count mismatch")
	}

	codecMessages := tx.Body.Messages
	for i, codecMsg := range codecMessages {
		handlerMsg := Message{
			Msg:      codecMsg,
			MsgIndex: i,
			MsgID:    fmt.Sprintf("%s-%d", hash, i),
			Log:      logs[i],
			TxHash:   hash,
			Events:   EventsMapFromStringEvents(logs[i].Events),
		}

		switch codecMsg.TypeUrl {
		case "/cosmwasm.wasm.v1.MsgInstantiateContract":
			if err := h.handleInstantiate(&handlerMsg); err != nil {
				return errors.Wrap(err, "failed to handle instantiate")
			}
		case "/cosmwasm.wasm.v1.MsgExecuteContract":
			if err := h.handleExecute(&handlerMsg); err != nil {
				return errors.Wrap(err, "failed to handle execute")
			}
		}
	}
	return nil
}

func (h *Handler) handleInstantiate(e *Message) error {
	var instantiateMsg wasmtypes.MsgInstantiateContract
	if err := cosmosproto.Unmarshal(e.Msg.Value, &instantiateMsg); err != nil {
		return errors.Wrap(err, "failed to unmarshal instantiate msg")
	}

	contractAddress, err := e.Events.InstantiateContractAddress()
	if err != nil {
		return errors.Wrap(err, "failed to get outer contract address")
	}

	switch contractAddress {
	case h.config.TNSContractAddress:
		if err := h.handleInstantiateTNS(e, contractAddress, &instantiateMsg); err != nil {
			return errors.Wrap(err, "failed to handle tns minter instantiation")
		}
		return nil
	}

	switch instantiateMsg.CodeID {
	case h.config.MinterCodeID:
		if err := h.handleInstantiateBunker(e, contractAddress, &instantiateMsg); err != nil {
			return errors.Wrap(err, "failed to handle minter instantiation")
		}
	default:
		h.logger.Debug("ignored instantiate with unknown code id", zap.Uint64("value", instantiateMsg.CodeID))
	}

	return nil
}

type ExecutePayload map[string]json.RawMessage

func (h *Handler) handleExecute(e *Message) error {
	var executeMsg wasmtypes.MsgExecuteContract
	if err := cosmosproto.Unmarshal(e.Msg.Value, &executeMsg); err != nil {
		return errors.Wrap(err, "failed to unmarshal execute msg")
	}

	var payload ExecutePayload
	if err := json.Unmarshal(executeMsg.Msg, &payload); err != nil {
		h.logger.Error("failed to unmarshal execute payload", zap.Error(err))
		return nil
	}
	if len(payload) != 1 {
		h.logger.Error("unexpected execute keys count", zap.Int("count", len(payload)))
		return nil
	}
	wasmAction := ""
	for key := range payload {
		wasmAction = key
	}

	switch wasmAction {
	case "mint":
		if err := h.handleExecuteMint(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle mint")
		}
	case "buy":
		if err := h.handleExecuteBuy(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle buy")
		}
	case "send_nft":
		if err := h.handleExecuteSendNFT(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle send_nft")
		}
	case "withdraw":
		if err := h.handleExecuteWithdraw(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle withdraw")
		}
	case "burn":
		if err := h.handleExecuteBurn(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle burn")
		}
	case "update_price":
		if err := h.handleExecuteUpdatePrice(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle update_price")
		}
	case "update_metadata":
		if err := h.handleExecuteUpdateMetadata(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle update_metadata")
		}
	case "update_primary_alias":
		if err := h.handleUpdatePrimaryAlias(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle update_primary_alias")
		}
	case "transfer_nft":
		if err := h.handleExecuteTransferNFT(e, &executeMsg); err != nil {
			return errors.Wrap(err, "failed to handle transfer")
		}
	}

	return nil
}

func (h *Handler) handleExecuteMint(e *Message, execMsg *wasmtypes.MsgExecuteContract) error {
	contractAddress := execMsg.Contract

	var collections []*indexerdb.Collection
	if err := h.db.Preload("TeritoriCollection").Limit(1).Find(&collections, &indexerdb.Collection{ID: indexerdb.TeritoriCollectionID(contractAddress)}).Error; err != nil {
		return errors.Wrap(err, "find collection error")
	}
	if len(collections) == 0 {
		h.logger.Debug("ignored mint from unknown collection", zap.String("address", contractAddress))
		return nil
	}
	collection := collections[0]
	if collection.TeritoriCollection == nil {
		spew.Dump(collection)
		return errors.New("no teritori info in collection")
	}

	// FIXME: do message analysis instead of events

	tokenIds := e.Events["wasm.token_id"]
	if len(tokenIds) == 0 {
		return errors.New("no token ids")
	}
	tokenId := tokenIds[0]

	if collection.TeritoriCollection != nil && collection.TeritoriCollection.MintContractAddress == h.config.TNSContractAddress {
		if err := h.handleExecuteMintTNS(e, collection, tokenId, execMsg); err != nil {
			return errors.Wrap(err, "failed to handle tns mint")
		}
		return nil
	}

	if err := h.handleExecuteMintBunker(e, collection, tokenId, execMsg); err != nil {
		return errors.Wrap(err, "failed to handle classic mint")
	}

	return nil
}
