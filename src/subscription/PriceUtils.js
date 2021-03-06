//@flow
import type {BookingItemFeatureTypeEnum, PaymentMethodTypeEnum} from "../api/common/TutanotaConstants"
import {InvoiceStatus, PaymentMethodType} from "../api/common/TutanotaConstants"
import {lang} from "../misc/LanguageViewModel.js"
import {formatPrice} from "../subscription/SubscriptionUtils"
import {showNotAvailableForFreeDialog} from "../misc/ErrorHandlerImpl"
import {logins} from "../api/main/LoginController"
import {Button} from "../gui/base/Button"
import {neverNull} from "../api/common/utils/Utils"
import type {lazyIcon} from "../gui/base/Icon"
import {isIOSApp} from "../api/Env"
import type {ButtonAttrs} from "../gui/base/ButtonN"
import type {TranslationKey} from "../misc/LanguageViewModel"

export function getPaymentMethodName(paymentMethod: ?PaymentMethodTypeEnum): string {
	if (paymentMethod === PaymentMethodType.Invoice) {
		return lang.get("paymentMethodOnAccount_label")
	} else if (paymentMethod === PaymentMethodType.CreditCard) {
		return lang.get("paymentMethodCreditCard_label")
	} else if (paymentMethod === PaymentMethodType.Sepa) {
		return "SEPA"
	} else if (paymentMethod === PaymentMethodType.Paypal) {
		return "PayPal"
	} else {
		return "<" + lang.get("comboBoxSelectionNone_msg") + ">"
	}
}

export function getPaymentMethodInfoText(accountingInfo: AccountingInfo): string {
	if (accountingInfo.paymentMethodInfo) {
		return accountingInfo.paymentMethod === PaymentMethodType.CreditCard ? lang.get("endsWith_label") + " "
			+ neverNull(accountingInfo.paymentMethodInfo) : neverNull(accountingInfo.paymentMethodInfo)
	} else {
		return ""
	}
}


export function formatPriceDataWithInfo(priceData: PriceData): string {
	return formatPriceWithInfo(Number(priceData.price), Number(priceData.paymentInterval), priceData.taxIncluded)
}

export function formatPriceWithInfo(price: number, paymentInterval: number, taxIncluded: boolean): string {
	const netOrGross = taxIncluded ? lang.get("gross_label") : lang.get("net_label")
	const yearlyOrMonthly = paymentInterval === 12 ? lang.get("pricing.perYear_label") : lang.get("pricing.perMonth_label")
	return formatPrice(price, true) + " " + yearlyOrMonthly + " (" + netOrGross + ")"
}

/**
 * Provides the price item from the given priceData for the given featureType. Returns null if no such item is available.
 */
export function getPriceItem(priceData: ?PriceData, featureType: NumberString): ?PriceItemData {
	if (priceData) {
		return priceData.items.find(item => {
			return (item.featureType === featureType)
		})
	} else {
		return null
	}
}

export function getCountFromPriceData(priceData: ?PriceData, featureType: BookingItemFeatureTypeEnum): number {
	const priceItem = getPriceItem(priceData, featureType)
	return priceItem ? Number(priceItem.count) : 0
}


/**
 * Returns the price for the feature type from the price data if available. otherwise 0.
 * @return The price
 */
export function getPriceFromPriceData(priceData: ?PriceData, featureType: NumberString): number {
	let item = getPriceItem(priceData, featureType);
	if (item) {
		return Number(item.price);
	} else {
		return 0;
	}
}

export function getCurrentCount(featureType: BookingItemFeatureTypeEnum, booking: ?Booking): number {
	if (booking) {
		let bookingItem = booking.items.find(item => item.featureType === featureType)
		return bookingItem ? Number(bookingItem.currentCount) : 0
	} else {
		return 0
	}
}

export function createNotAvailableForFreeButton(labelId: string, buyAction: clickHandler, icon: lazyIcon, isInPremiumIncluded: boolean): Button {
	return new Button(labelId, () => {
		if (logins.getUserController().isFreeAccount() || isIOSApp()) {
			showNotAvailableForFreeDialog(isInPremiumIncluded)
		} else {
			buyAction()
		}
	}, icon)
}

export function createNotAvailableForFreeButtonAttrs(labelId: TranslationKey, buyAction: clickHandler, icon: lazyIcon, isInPremiumIncluded: boolean): ButtonAttrs {
	return {
		label: labelId,
		click: () => {
			if (logins.getUserController().isFreeAccount() || isIOSApp()) {
				showNotAvailableForFreeDialog(isInPremiumIncluded)
			} else {
				buyAction()
			}
		},
		icon: icon
	}
}


export function getInvoiceStatusText(invoice: Invoice): string {
	if (invoice.status === InvoiceStatus.PUBLISHEDFORAUTOMATIC
		|| invoice.status === InvoiceStatus.PUBLISHEDFORMANUAL
		|| invoice.status === InvoiceStatus.CREATED) {
		return lang.get('invoiceStateOpen_label')
	} else if (invoice.status === InvoiceStatus.DEBITFAILED || invoice.status === InvoiceStatus.FIRSTREMINDER
		|| invoice.status === InvoiceStatus.SECONDREMINDER) {
		return lang.get('invoiceStatePaymentFailed_label')
	} else if (invoice.status === InvoiceStatus.PAID) {
		return lang.get('invoiceStatePaid_label')
	} else if (invoice.status === InvoiceStatus.DISPUTED) {
		return lang.get('invoiceStateResolving_label')
	} else if (invoice.status === InvoiceStatus.REFUNDED || invoice.status === InvoiceStatus.DISPUTEACCEPTED) {
		return lang.get('invoiceStateRefunded_label')
	} else if (invoice.status === InvoiceStatus.CANCELLED) {
		return lang.get('invoiceStateCancelled_label')
	} else {
		return "";
	}
}