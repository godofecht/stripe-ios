//
// VerificationPageStaticContentIndividualPage.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Foundation
@_spi(STP) import StripeCore



struct VerificationPageStaticContentIndividualPage: StripeDecodable, Equatable {
    var addressCountries: [String:String]
    var buttonText: String
    var idNumberCountries: [String:String]
    var title: String
    var _allResponseFieldsStorage: NonEncodableParameters?
}
