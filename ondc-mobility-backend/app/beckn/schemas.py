from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime


class BecknContext(BaseModel):
    domain: str = Field(default="ONDC:TRV11")
    location: Optional[Dict[str, Any]] = None
    action: str
    country: str = Field(default="IND")
    city: str = Field(default="std:040")  # Default Hyderabad, std:080 for Bengaluru
    core_version: str = Field(default="2.0.0")
    bap_id: str
    bap_uri: str
    bpp_id: Optional[str] = None
    bpp_uri: Optional[str] = None
    transaction_id: str
    message_id: str
    timestamp: str
    ttl: Optional[str] = "PT30S"


# ACK / Error Schemas
class BecknAck(BaseModel):
    status: str = Field(default="ACK")  # ACK or NACK


class BecknAckMessage(BaseModel):
    ack: BecknAck


class BecknError(BaseModel):
    type: str = "CONTEXT-ERROR"
    code: str
    path: Optional[str] = None
    message: str


class BecknAckResponse(BaseModel):
    message: BecknAckMessage
    error: Optional[BecknError] = None


# SEARCH Schemas
class LocationDescriptor(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None


class StationLocation(BaseModel):
    id: str
    descriptor: Optional[LocationDescriptor] = None
    gps: Optional[str] = None


class FulfillmentStartEnd(BaseModel):
    location: StationLocation


class SearchFulfillment(BaseModel):
    start: FulfillmentStartEnd
    end: FulfillmentStartEnd


class SearchIntent(BaseModel):
    fulfillment: SearchFulfillment


class SearchMessage(BaseModel):
    intent: SearchIntent


class BecknSearchRequest(BaseModel):
    context: BecknContext
    message: SearchMessage


# ON_SEARCH Schemas
class ItemPrice(BaseModel):
    currency: str = "INR"
    value: str


class CatalogItem(BaseModel):
    id: str
    descriptor: Dict[str, Any]
    price: ItemPrice
    time: Optional[Dict[str, Any]] = None


class CatalogProvider(BaseModel):
    id: str
    descriptor: Dict[str, Any]
    items: List[CatalogItem]


class OnSearchCatalog(BaseModel):
    bpp_providers: List[CatalogProvider]


class OnSearchMessage(BaseModel):
    catalog: OnSearchCatalog


class BecknOnSearchRequest(BaseModel):
    context: BecknContext
    message: OnSearchMessage
    error: Optional[BecknError] = None


# SELECT Schemas
class SelectSelectedItem(BaseModel):
    id: str
    quantity: Dict[str, int] = Field(default={"count": 1})


class SelectOrder(BaseModel):
    items: List[SelectSelectedItem]
    provider: Dict[str, str]


class SelectMessage(BaseModel):
    order: SelectOrder


class BecknSelectRequest(BaseModel):
    context: BecknContext
    message: SelectMessage


# ON_SELECT Schemas
class PriceBreakup(BaseModel):
    title: str
    price: ItemPrice


class OrderQuote(BaseModel):
    price: ItemPrice
    breakup: List[PriceBreakup]


class OnSelectOrder(BaseModel):
    provider: Dict[str, Any]
    items: List[CatalogItem]
    quote: OrderQuote


class OnSelectMessage(BaseModel):
    order: OnSelectOrder


class BecknOnSelectRequest(BaseModel):
    context: BecknContext
    message: OnSelectMessage
    error: Optional[BecknError] = None


# INIT Schemas
class BillingCustomer(BaseModel):
    name: str
    phone: str
    email: Optional[str] = None


class InitOrder(BaseModel):
    provider: Dict[str, str]
    items: List[SelectSelectedItem]
    billing: BillingCustomer


class InitMessage(BaseModel):
    order: InitOrder


class BecknInitRequest(BaseModel):
    context: BecknContext
    message: InitMessage


# ON_INIT Schemas
class PaymentSettlementDetails(BaseModel):
    settlement_counterparty: Optional[str] = "seller-app"
    settlement_phase: Optional[str] = "sale-amount"
    settlement_type: Optional[str] = "neft"
    beneficiary_name: Optional[str] = None
    bank_account_number: Optional[str] = None
    ifsc_code: Optional[str] = None


class OnInitPayment(BaseModel):
    type: str = "ON-FULFILLMENT"
    status: str = "NOT-PAID"
    collected_by: str = "BAP"
    settlement_details: Optional[List[PaymentSettlementDetails]] = None


class OnInitOrder(BaseModel):
    provider: Dict[str, Any]
    items: List[CatalogItem]
    quote: OrderQuote
    payment: OnInitPayment


class OnInitMessage(BaseModel):
    order: OnInitOrder


class BecknOnInitRequest(BaseModel):
    context: BecknContext
    message: OnInitMessage
    error: Optional[BecknError] = None


# CONFIRM Schemas
class ConfirmPayment(BaseModel):
    params: Dict[str, str]  # e.g., transaction_id, amount
    type: str = "ON-FULFILLMENT"
    status: str = "PAID"
    collected_by: str = "BAP"


class ConfirmOrder(BaseModel):
    provider: Dict[str, str]
    items: List[SelectSelectedItem]
    billing: BillingCustomer
    payment: ConfirmPayment


class ConfirmMessage(BaseModel):
    order: ConfirmOrder


class BecknConfirmRequest(BaseModel):
    context: BecknContext
    message: ConfirmMessage


# ON_CONFIRM Schemas
class FulfillmentState(BaseModel):
    descriptor: Dict[str, str]


class FulfillmentStop(BaseModel):
    location: StationLocation
    time: Optional[Dict[str, Any]] = None


class TicketFulfillment(BaseModel):
    id: str
    type: str = "RIDE"
    state: FulfillmentState
    stops: List[FulfillmentStop]
    vehicle: Optional[Dict[str, Any]] = None
    customer: Optional[Dict[str, Any]] = None
    # Encrypted QR Payload stored here or in item fulfillment
    tokens: Optional[List[Dict[str, Any]]] = None


class OnConfirmOrder(BaseModel):
    id: str
    state: str = "ACCEPTED"
    provider: Dict[str, Any]
    items: List[CatalogItem]
    fulfillments: List[TicketFulfillment]
    quote: OrderQuote
    payment: ConfirmPayment


class OnConfirmMessage(BaseModel):
    order: OnConfirmOrder


class BecknOnConfirmRequest(BaseModel):
    context: BecknContext
    message: OnConfirmMessage
    error: Optional[BecknError] = None


# STATUS Schemas
class StatusMessage(BaseModel):
    order_id: str


class BecknStatusRequest(BaseModel):
    context: BecknContext
    message: StatusMessage


class BecknOnStatusRequest(BaseModel):
    context: BecknContext
    message: OnConfirmMessage  # Status returns updated order model
    error: Optional[BecknError] = None
