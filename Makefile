.PHONY: all build test clean anvil-local anvil-stop deploy-libraries-step1-local deploy-libraries-step2-local deploy-libraries-local deploy-dao-local deploy-multisig-local deploy-price-oracle-local set-creator-local set-price-oracle-local deploy-whitelist-oracles-local deploy-private-sale-local deploy-return-wallet-local set-market-maker-local deploy-all-local deploy-libraries-step1-polygon deploy-libraries-step2-polygon deploy-libraries-polygon deploy-dao-polygon deploy-multisig-polygon deploy-price-oracle-polygon set-creator-polygon set-price-oracle-polygon deploy-whitelist-oracles-polygon deploy-private-sale-polygon deploy-return-wallet-polygon set-market-maker-polygon deploy-all-polygon deploy-libraries-step1-bsc deploy-libraries-step2-bsc deploy-libraries-bsc deploy-dao-bsc deploy-multisig-bsc deploy-price-oracle-bsc set-creator-bsc set-price-oracle-bsc deploy-whitelist-oracles-bsc deploy-private-sale-bsc deploy-return-wallet-bsc set-market-maker-bsc deploy-all-bsc deploy-libraries-step1-bsc-testnet deploy-libraries-step2-bsc-testnet deploy-libraries-bsc-testnet deploy-dao-bsc-testnet deploy-multisig-bsc-testnet deploy-price-oracle-bsc-testnet set-creator-bsc-testnet set-price-oracle-bsc-testnet deploy-whitelist-oracles-bsc-testnet deploy-private-sale-bsc-testnet deploy-return-wallet-bsc-testnet set-market-maker-bsc-testnet deploy-all-bsc-testnet help

-include .env

LOCAL_RPC_URL := http://127.0.0.1:8545
POLYGON_RPC := ${RPC_URL_POLYGON}
BSC_RPC := ${RPC_URL_BSC}
BSC_TESTNET_RPC := ${RPC_URL_BSC_TESTNET}
PRIVATE_KEY := ${PRIVATE_KEY}

LIBRARIES_STEP1_SCRIPT := script/DeployLibrariesStep1.s.sol
LIBRARIES_STEP2_SCRIPT := script/DeployLibrariesStep2.s.sol
DAO_SCRIPT := script/DeployDAO.s.sol
MULTISIG_SCRIPT := script/DeployMultisig.s.sol
PRICE_ORACLE_SCRIPT := script/DeployPriceOracle.s.sol
SET_CREATOR_SCRIPT := script/SetCreator.s.sol
PRIVATE_SALE_SCRIPT := script/DeployPrivateSale.s.sol
RETURN_WALLET_SCRIPT := script/DeployReturnWallet.s.sol
SET_MARKET_MAKER_SCRIPT := script/SetMarketMaker.s.sol
SET_PRICE_ORACLE_SCRIPT := script/SetPriceOracle.s.sol
WHITELIST_ORACLES_SCRIPT := script/DeployWhitelistOracles.s.sol

# Проверяем наличие файла с адресами библиотек
ifneq ("$(wildcard ./.library_addresses.env)","")
  include ./.library_addresses.env
endif

# Проверяем наличие файла с адресами деплоя
ifneq ("$(wildcard ./.deployment_addresses.env)","")
  include ./.deployment_addresses.env
endif

all: help

build:
	@echo "Building contracts..."
	forge build

test:
	@echo "Running tests..."
	forge test -vvv

clean:
	@echo "Cleaning build artifacts..."
	forge clean

help:
	@echo "Available commands:"
	@echo "  make build          - Build contracts"
	@echo "  make test           - Run tests"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make anvil-local    - Start local Anvil node"
	@echo "  make anvil-stop     - Stop local Anvil node"
	@echo ""
	@echo "Deployment commands for LOCAL:"
	@echo "  make deploy-libraries-step1-local - Deploy libraries without dependencies"
	@echo "  make deploy-libraries-step2-local - Deploy libraries with dependencies"
	@echo "  make deploy-libraries-local      - Deploy all libraries"
	@echo "  make deploy-dao-local            - Deploy DAO"
	@echo "  make deploy-multisig-local        - Deploy Multisig"
	@echo "  make deploy-price-oracle-local    - Deploy PriceOracle"
	@echo "  make set-creator-local            - Set creator in DAO"
	@echo "  make set-price-oracle-local       - Set price oracle in DAO"
	@echo "  make deploy-whitelist-oracles-local - Deploy WhitelistOracles"
	@echo "  make deploy-private-sale-local   - Deploy PrivateSale"
	@echo "  make deploy-return-wallet-local   - Deploy ReturnWallet"
	@echo "  make set-market-maker-local       - Set market maker in DAO"
	@echo "  make deploy-all-local             - Deploy all contracts"
	@echo ""
	@echo "Deployment commands for POLYGON:"
	@echo "  make deploy-libraries-step1-polygon - Deploy libraries without dependencies"
	@echo "  make deploy-libraries-step2-polygon - Deploy libraries with dependencies"
	@echo "  make deploy-libraries-polygon      - Deploy all libraries"
	@echo "  make deploy-dao-polygon            - Deploy DAO"
	@echo "  make deploy-multisig-polygon        - Deploy Multisig"
	@echo "  make deploy-price-oracle-polygon    - Deploy PriceOracle"
	@echo "  make set-creator-polygon            - Set creator in DAO"
	@echo "  make set-price-oracle-polygon       - Set price oracle in DAO"
	@echo "  make deploy-whitelist-oracles-polygon - Deploy WhitelistOracles"
	@echo "  make deploy-private-sale-polygon   - Deploy PrivateSale"
	@echo "  make deploy-return-wallet-polygon   - Deploy ReturnWallet"
	@echo "  make set-market-maker-polygon      - Set market maker in DAO"
	@echo "  make deploy-all-polygon             - Deploy all contracts"
	@echo ""
	@echo "Deployment commands for BSC:"
	@echo "  make deploy-libraries-step1-bsc - Deploy libraries without dependencies"
	@echo "  make deploy-libraries-step2-bsc - Deploy libraries with dependencies"
	@echo "  make deploy-libraries-bsc      - Deploy all libraries"
	@echo "  make deploy-dao-bsc            - Deploy DAO"
	@echo "  make deploy-multisig-bsc        - Deploy Multisig"
	@echo "  make deploy-price-oracle-bsc    - Deploy PriceOracle"
	@echo "  make set-creator-bsc            - Set creator in DAO"
	@echo "  make set-price-oracle-bsc       - Set price oracle in DAO"
	@echo "  make deploy-whitelist-oracles-bsc - Deploy WhitelistOracles"
	@echo "  make deploy-private-sale-bsc   - Deploy PrivateSale"
	@echo "  make deploy-return-wallet-bsc   - Deploy ReturnWallet"
	@echo "  make set-market-maker-bsc      - Set market maker in DAO"
	@echo "  make deploy-all-bsc            - Deploy all contracts"
	@echo ""
	@echo "Deployment commands for BSC-TESTNET:"
	@echo "  make deploy-libraries-step1-bsc-testnet - Deploy libraries without dependencies"
	@echo "  make deploy-libraries-step2-bsc-testnet - Deploy libraries with dependencies"
	@echo "  make deploy-libraries-bsc-testnet      - Deploy all libraries"
	@echo "  make deploy-dao-bsc-testnet            - Deploy DAO"
	@echo "  make deploy-multisig-bsc-testnet        - Deploy Multisig"
	@echo "  make deploy-price-oracle-bsc-testnet    - Deploy PriceOracle"
	@echo "  make set-creator-bsc-testnet            - Set creator in DAO"
	@echo "  make set-price-oracle-bsc-testnet       - Set price oracle in DAO"
	@echo "  make deploy-whitelist-oracles-bsc-testnet - Deploy WhitelistOracles"
	@echo "  make deploy-private-sale-bsc-testnet   - Deploy PrivateSale"
	@echo "  make deploy-return-wallet-bsc-testnet   - Deploy ReturnWallet"
	@echo "  make set-market-maker-bsc-testnet      - Set market maker in DAO"
	@echo "  make deploy-all-bsc-testnet            - Deploy all contracts"

# ============================================
# LOCAL DEPLOYMENT
# ============================================

anvil-local:
	@echo "Starting Anvil local node..."
	@if [ -f .anvil.pid ]; then \
		PID=$$(cat .anvil.pid); \
		if ps -p $$PID > /dev/null 2>&1; then \
			echo "Anvil is already running (PID: $$PID)"; \
		else \
			rm -f .anvil.pid; \
			anvil --host 127.0.0.1 --port 8545 > /dev/null 2>&1 & \
			echo $$! > .anvil.pid; \
			echo "Anvil started on http://127.0.0.1:8545 (PID: $$!)"; \
			sleep 2; \
		fi; \
	else \
		anvil --host 127.0.0.1 --port 8545 > /dev/null 2>&1 & \
		echo $$! > .anvil.pid; \
		echo "Anvil started on http://127.0.0.1:8545 (PID: $$!)"; \
		sleep 2; \
	fi

anvil-stop:
	@echo "Stopping Anvil local node..."
	@if [ -f .anvil.pid ]; then \
		PID=$$(cat .anvil.pid); \
		if ps -p $$PID > /dev/null 2>&1; then \
			kill $$PID 2>/dev/null || true; \
			echo "Anvil stopped (PID: $$PID)"; \
		else \
			echo "Anvil process not found (PID: $$PID)"; \
		fi; \
		rm -f .anvil.pid; \
	else \
		echo "Anvil is not running (no PID file found)"; \
	fi

deploy-libraries-step1-local:
	@echo "Deploying libraries step1 to local network..."
	forge script ${LIBRARIES_STEP1_SCRIPT} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--ffi \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-step2-local:
	@echo "Deploying libraries step2 to local network..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
		forge script ${LIBRARIES_STEP2_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:$${vaultLibrary} \
			--libraries src/libraries/external/Orderbook.sol:Orderbook:$${orderbook} \
			--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:$${oracleLibrary} \
			-vvv; \
	else \
		echo "Error: ./.library_addresses.env not found. Run deploy-libraries-step1-local first."; \
		exit 1; \
	fi
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-local: deploy-libraries-step1-local deploy-libraries-step2-local

deploy-dao-local:
	@echo "Deploying DAO to local network..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
		forge script ${DAO_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:$${vaultLibrary} \
			--libraries src/libraries/external/Orderbook.sol:Orderbook:$${orderbook} \
			--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:$${oracleLibrary} \
			--libraries src/libraries/external/POCLibrary.sol:POCLibrary:$${pocLibrary} \
			--libraries src/libraries/external/FundraisingLibrary.sol:FundraisingLibrary:$${fundraisingLibrary} \
			--libraries src/libraries/external/ExitQueueLibrary.sol:ExitQueueLibrary:$${exitQueueLibrary} \
			--libraries src/libraries/external/LPTokenLibrary.sol:LPTokenLibrary:$${lpTokenLibrary} \
			--libraries src/libraries/external/ProfitDistributionLibrary.sol:ProfitDistributionLibrary:$${profitDistributionLibrary} \
			--libraries src/libraries/external/RewardsLibrary.sol:RewardsLibrary:$${rewardsLibrary} \
			--libraries src/libraries/external/DissolutionLibrary.sol:DissolutionLibrary:$${dissolutionLibrary} \
			--libraries src/libraries/external/CreatorLibrary.sol:CreatorLibrary:$${creatorLibrary} \
			-vvv; \
	else \
		echo "Error: ./.library_addresses.env not found. Run deploy-libraries-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-multisig-local:
	@echo "Deploying Multisig to local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${MULTISIG_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-price-oracle-local:
	@echo "Deploying PriceOracle to local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${PRICE_ORACLE_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-creator-local:
	@echo "Setting creator in DAO on local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${SET_CREATOR_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-private-sale-local:
	@echo "Deploying PrivateSale to local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${PRIVATE_SALE_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-return-wallet-local:
	@echo "Deploying ReturnWallet to local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${RETURN_WALLET_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-market-maker-local:
	@echo "Setting market maker in DAO on local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${SET_MARKET_MAKER_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-price-oracle-local:
	@echo "Setting price oracle in DAO on local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${SET_PRICE_ORACLE_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi

deploy-whitelist-oracles-local:
	@echo "Deploying WhitelistOracles to local network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
		forge script ${WHITELIST_ORACLES_SCRIPT} \
			--rpc-url ${LOCAL_RPC_URL} \
			--private-key ${PRIVATE_KEY} \
			--broadcast \
			--ffi \
			-vvv; \
	else \
		echo "Error: ./.deployment_addresses.env not found. Run deploy-dao-local first."; \
		exit 1; \
	fi
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-all-local: deploy-libraries-local
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-dao-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-multisig-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-creator-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-whitelist-oracles-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-price-oracle-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-price-oracle-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-private-sale-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-return-wallet-local
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-market-maker-local

# ============================================
# POLYGON DEPLOYMENT
# ============================================

deploy-libraries-step1-polygon:
	@echo "Deploying libraries step1 to Polygon network..."
	forge script ${LIBRARIES_STEP1_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-step2-polygon:
	@echo "Deploying libraries step2 to Polygon network..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	forge script ${LIBRARIES_STEP2_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:${vaultLibrary} \
		--libraries src/libraries/external/Orderbook.sol:Orderbook:${orderbook} \
		--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:${oracleLibrary} \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-polygon: deploy-libraries-step1-polygon deploy-libraries-step2-polygon

deploy-dao-polygon:
	@echo "Deploying DAO to Polygon network..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	forge script ${DAO_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:${vaultLibrary} \
		--libraries src/libraries/external/Orderbook.sol:Orderbook:${orderbook} \
		--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:${oracleLibrary} \
		--libraries src/libraries/external/POCLibrary.sol:POCLibrary:${pocLibrary} \
		--libraries src/libraries/external/FundraisingLibrary.sol:FundraisingLibrary:${fundraisingLibrary} \
		--libraries src/libraries/external/ExitQueueLibrary.sol:ExitQueueLibrary:${exitQueueLibrary} \
		--libraries src/libraries/external/LPTokenLibrary.sol:LPTokenLibrary:${lpTokenLibrary} \
		--libraries src/libraries/external/ProfitDistributionLibrary.sol:ProfitDistributionLibrary:${profitDistributionLibrary} \
		--libraries src/libraries/external/RewardsLibrary.sol:RewardsLibrary:${rewardsLibrary} \
		--libraries src/libraries/external/DissolutionLibrary.sol:DissolutionLibrary:${dissolutionLibrary} \
		--libraries src/libraries/external/CreatorLibrary.sol:CreatorLibrary:${creatorLibrary} \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-multisig-polygon:
	@echo "Deploying Multisig to Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${MULTISIG_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-price-oracle-polygon:
	@echo "Deploying PriceOracle to Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${PRICE_ORACLE_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-creator-polygon:
	@echo "Setting creator in DAO on Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_CREATOR_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-price-oracle-polygon:
	@echo "Setting price oracle in DAO on Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_PRICE_ORACLE_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-whitelist-oracles-polygon:
	@echo "Deploying WhitelistOracles to Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${WHITELIST_ORACLES_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-private-sale-polygon:
	@echo "Deploying PrivateSale to Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${PRIVATE_SALE_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-return-wallet-polygon:
	@echo "Deploying ReturnWallet to Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${RETURN_WALLET_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-market-maker-polygon:
	@echo "Setting market maker in DAO on Polygon network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_MARKET_MAKER_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-all-polygon: deploy-libraries-polygon
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-dao-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-multisig-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-creator-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-whitelist-oracles-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-price-oracle-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-price-oracle-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-private-sale-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-return-wallet-polygon
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-market-maker-polygon

# ============================================
# BSC DEPLOYMENT
# ============================================

deploy-libraries-step1-bsc:
	@echo "Deploying libraries step1 to BSC network..."
	forge script ${LIBRARIES_STEP1_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-step2-bsc:
	@echo "Deploying libraries step2 to BSC network..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	forge script ${LIBRARIES_STEP2_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:${vaultLibrary} \
		--libraries src/libraries/external/Orderbook.sol:Orderbook:${orderbook} \
		--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:${oracleLibrary} \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-bsc: deploy-libraries-step1-bsc deploy-libraries-step2-bsc

deploy-dao-bsc:
	@echo "Deploying DAO to BSC network..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	forge script ${DAO_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:${vaultLibrary} \
		--libraries src/libraries/external/Orderbook.sol:Orderbook:${orderbook} \
		--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:${oracleLibrary} \
		--libraries src/libraries/external/POCLibrary.sol:POCLibrary:${pocLibrary} \
		--libraries src/libraries/external/FundraisingLibrary.sol:FundraisingLibrary:${fundraisingLibrary} \
		--libraries src/libraries/external/ExitQueueLibrary.sol:ExitQueueLibrary:${exitQueueLibrary} \
		--libraries src/libraries/external/LPTokenLibrary.sol:LPTokenLibrary:${lpTokenLibrary} \
		--libraries src/libraries/external/ProfitDistributionLibrary.sol:ProfitDistributionLibrary:${profitDistributionLibrary} \
		--libraries src/libraries/external/RewardsLibrary.sol:RewardsLibrary:${rewardsLibrary} \
		--libraries src/libraries/external/DissolutionLibrary.sol:DissolutionLibrary:${dissolutionLibrary} \
		--libraries src/libraries/external/CreatorLibrary.sol:CreatorLibrary:${creatorLibrary} \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-multisig-bsc:
	@echo "Deploying Multisig to BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${MULTISIG_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-price-oracle-bsc:
	@echo "Deploying PriceOracle to BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${PRICE_ORACLE_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-creator-bsc:
	@echo "Setting creator in DAO on BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_CREATOR_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-price-oracle-bsc:
	@echo "Setting price oracle in DAO on BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_PRICE_ORACLE_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-whitelist-oracles-bsc:
	@echo "Deploying WhitelistOracles to BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${WHITELIST_ORACLES_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-private-sale-bsc:
	@echo "Deploying PrivateSale to BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${PRIVATE_SALE_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-return-wallet-bsc:
	@echo "Deploying ReturnWallet to BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${RETURN_WALLET_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-market-maker-bsc:
	@echo "Setting market maker in DAO on BSC network..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_MARKET_MAKER_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-all-bsc: deploy-libraries-bsc
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-dao-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-multisig-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-creator-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-whitelist-oracles-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-price-oracle-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-price-oracle-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-private-sale-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-return-wallet-bsc
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-market-maker-bsc

# ============================================
# BSC TESTNET DEPLOYMENT
# ============================================

deploy-libraries-step1-bsc-testnet:
	@echo "Deploying libraries step1 to BSC testnet..."
	forge script ${LIBRARIES_STEP1_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-step2-bsc-testnet:
	@echo "Deploying libraries step2 to BSC testnet..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	forge script ${LIBRARIES_STEP2_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:${vaultLibrary} \
		--libraries src/libraries/external/Orderbook.sol:Orderbook:${orderbook} \
		--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:${oracleLibrary} \
		-vvv
	@if [ -f ./.library_addresses.env ]; then \
		echo "Library addresses successfully saved. Contents:"; \
		cat ./.library_addresses.env; \
	fi

deploy-libraries-bsc-testnet: deploy-libraries-step1-bsc-testnet deploy-libraries-step2-bsc-testnet

deploy-dao-bsc-testnet:
	@echo "Deploying DAO to BSC testnet..."
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	forge script ${DAO_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		--libraries src/libraries/external/VaultLibrary.sol:VaultLibrary:${vaultLibrary} \
		--libraries src/libraries/external/Orderbook.sol:Orderbook:${orderbook} \
		--libraries src/libraries/external/OracleLibrary.sol:OracleLibrary:${oracleLibrary} \
		--libraries src/libraries/external/POCLibrary.sol:POCLibrary:${pocLibrary} \
		--libraries src/libraries/external/FundraisingLibrary.sol:FundraisingLibrary:${fundraisingLibrary} \
		--libraries src/libraries/external/ExitQueueLibrary.sol:ExitQueueLibrary:${exitQueueLibrary} \
		--libraries src/libraries/external/LPTokenLibrary.sol:LPTokenLibrary:${lpTokenLibrary} \
		--libraries src/libraries/external/ProfitDistributionLibrary.sol:ProfitDistributionLibrary:${profitDistributionLibrary} \
		--libraries src/libraries/external/RewardsLibrary.sol:RewardsLibrary:${rewardsLibrary} \
		--libraries src/libraries/external/DissolutionLibrary.sol:DissolutionLibrary:${dissolutionLibrary} \
		--libraries src/libraries/external/CreatorLibrary.sol:CreatorLibrary:${creatorLibrary} \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-multisig-bsc-testnet:
	@echo "Deploying Multisig to BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${MULTISIG_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-price-oracle-bsc-testnet:
	@echo "Deploying PriceOracle to BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${PRICE_ORACLE_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-creator-bsc-testnet:
	@echo "Setting creator in DAO on BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_CREATOR_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-price-oracle-bsc-testnet:
	@echo "Setting price oracle in DAO on BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_PRICE_ORACLE_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-whitelist-oracles-bsc-testnet:
	@echo "Deploying WhitelistOracles to BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${WHITELIST_ORACLES_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-private-sale-bsc-testnet:
	@echo "Deploying PrivateSale to BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${PRIVATE_SALE_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-return-wallet-bsc-testnet:
	@echo "Deploying ReturnWallet to BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${RETURN_WALLET_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

set-market-maker-bsc-testnet:
	@echo "Setting market maker in DAO on BSC testnet..."
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	forge script ${SET_MARKET_MAKER_SCRIPT} \
		--rpc-url ${BSC_TESTNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv
	@if [ -f ./.deployment_addresses.env ]; then \
		echo "Deployment addresses successfully saved. Contents:"; \
		cat ./.deployment_addresses.env; \
	fi

deploy-all-bsc-testnet: deploy-libraries-bsc-testnet
	@if [ -f ./.library_addresses.env ]; then \
		set -a; \
		. ./.library_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-dao-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-multisig-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-creator-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-whitelist-oracles-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-price-oracle-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-price-oracle-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-private-sale-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) deploy-return-wallet-bsc-testnet
	@if [ -f ./.deployment_addresses.env ]; then \
		set -a; \
		. ./.deployment_addresses.env; \
		set +a; \
	fi
	$(MAKE) set-market-maker-bsc-testnet
