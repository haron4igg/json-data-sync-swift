//
//  Query.swift
//  Spine
//
//  Created by Ward van Teijlingen on 30-08-14.
//  Copyright (c) 2014 Ward van Teijlingen. All rights reserved.
//

import Foundation

/**
A Query defines search criteria used to retrieve data from an API.

Custom query URL
================
Usually Query objects are turned into URLs by the Router. The Router decides how the query configurations
are translated to URL components. However, queries can also be instantiated with a custom URL.
This is used when the API returns hrefs for example. Custom URL components will not be 'parsed'
into their respective configuration variables, so the query configuration may not correspond to
the actual URL generated by the Router.
*/
public struct Query<T: Resource> {
	
	/// The type of resource to fetch. This can be nil if in case of an expected heterogenous response.
	var resourceType: ResourceType?

	/// The specific IDs the fetch.
	var resourceIDs: [String]?
	
	/// The optional base URL
	internal var URL: NSURL?
	
	/// Related resources that must be included in a compound document.
	public internal(set) var includes: [String] = []
	
	/// Comparison predicates used to filter resources.
	public internal(set) var filters: [NSComparisonPredicate] = []
	
	/// Fields that will be returned, per resource type. If no fields are specified, all fields are returned.
	public internal(set) var fields: [ResourceType: [String]] = [:]
	
	/// Sort descriptors to sort resources.
	public internal(set) var sortDescriptors: [NSSortDescriptor] = []
	
	public internal(set) var pagination: Pagination?
	
	
	//MARK: Init
	
	/**
	Inits a new query for the given resource type and optional resource IDs.
	
	- parameter resourceType: The type of resource to query.
	- parameter resourceIDs:  The IDs of the resources to query. Pass nil to fetch all resources of the given type.
	
	- returns: Query
	*/
	public init(resourceType: T.Type, resourceIDs: [String]? = nil) {
		self.resourceType = resourceType.resourceType
		self.resourceIDs = resourceIDs
	}
	
	/**
	Inits a new query that fetches the given resource.
	
	- parameter resource: The resource to fetch.
	
	- returns: Query
	*/
	public init(resource: T) {
		assert(resource.id != nil, "Cannot instantiate query for resource, id is nil.")
		self.resourceType = resource.resourceType
		self.URL = resource.URL
		self.resourceIDs = [resource.id!]
	}
	
	/**
	Inits a new query that fetches resources from the given resource collection.
	
	- parameter resourceCollection: The resource collection whose resources to fetch.
	
	- returns: Query
	*/
	public init(resourceType: T.Type, resourceCollection: ResourceCollection) {
		self.resourceType = T.resourceType
		self.URL = resourceCollection.resourcesURL
	}
	
	/**
	Inits a new query that fetches resource of type `resourceType`, by using the given URL.
	
	- parameter resourceType: The type of resource to query.
	- parameter URL:          The URL used to fetch the resources.
	
	- returns: Query
	*/
	public init(resourceType: T.Type, path: String) {
		self.resourceType = T.resourceType
		self.URL = NSURL(string: path)
	}
	
	internal init(URL: NSURL) {
		self.URL = URL
	}
	
	
	// MARK: Sideloading
	
	/**
	Includes the given relation in the query. This will fetch resources that are in that relationship.
	
	Non-nested relationships should be specified as the name of the relationship in the Swift model.
	Nested relationships (eg. post.author), should instead be specified using the serialized names.
	
	- parameter relation: The name of the relation to include.
	
	- returns: The query.
	*/
	public mutating func include(relationshipNames: String...) {
		for relationshipName in relationshipNames {
			if relationshipName.characters.contains(".") {
				includes.append(relationshipName)
			} else if let relationship = T.fields.filter({ $0.name == relationshipName }).first {
				includes.append(relationship.serializedName)
			} else {
				assertionFailure("Resource of type \(T.resourceType) does not contain a relationship named \(relationshipName)")
			}
		}
	}
	
	/**
	Removes a previously included relation.
	
	Non-nested relationships should be specified as the name of the relationship in the Swift model.
	Nested relationships (eg. post.author), should instead be specified using the serialized names.
	
	- parameter relation: The name of the included relationship to remove.
	
	- returns: The query
	*/
	public mutating func removeInclude(relationshipNames: String...) {
		for relationshipName in relationshipNames {
			if relationshipName.characters.contains(".") {
				if let index = includes.indexOf(relationshipName) {
					includes.removeAtIndex(index)
				} else {
					assertionFailure("Attempt to remove include that was not included: \(relationshipName)")
				}
			} else if let relationship = T.fields.filter({ $0.name == relationshipName }).first {
				if let index = includes.indexOf(relationship.serializedName) {
					includes.removeAtIndex(index)
				} else {
					assertionFailure("Attempt to remove include that was not included: \(relationshipName)")
				}
			} else {
				assertionFailure("Resource of type \(T.resourceType) does not contain a relationship named \(relationshipName)")
			}
		}
	}
	
	
	// MARK: Filtering
	
	private mutating func addPredicateWithField(fieldName: String, value: AnyObject, type: NSPredicateOperatorType) {
		if let field = T.fields.filter({ $0.name == fieldName }).first {
			let predicate = NSComparisonPredicate(
				leftExpression: NSExpression(forKeyPath: field.serializedName),
				rightExpression: NSExpression(forConstantValue: value),
				modifier: .DirectPredicateModifier,
				type: type,
				options: [])
			
			addPredicate(predicate)
		} else {
			assertionFailure("Resource of type \(T.resourceType) does not contain a field named \(fieldName)")
		}
	}
	
	/**
	Adds the given predicate as a filter.
	
	- parameter predicate: The predicate to add.
	*/
	public mutating func addPredicate(predicate: NSComparisonPredicate) {
		filters.append(predicate)
	}
	
	/**
	Adds a filter where the given attribute should be equal to the given value.
	
	- parameter attributeName: The name of the attribute to filter on.
	- parameter equals:        The value to check for.
	
	- returns: The query
	*/
	public mutating func whereAttribute(attributeName: String, equalTo: AnyObject) {
		addPredicateWithField(attributeName, value: equalTo, type: .EqualToPredicateOperatorType)
	}

	/**
	Adds a filter where the given attribute should not be equal to the given value.
	
	- parameter attributeName: The name of the attribute to filter on.
	- parameter equals:        The value to check for.
	
	- returns: The query
	*/
	public mutating func whereAttribute(attributeName: String, notEqualTo: AnyObject) {
		addPredicateWithField(attributeName, value: notEqualTo, type: .NotEqualToPredicateOperatorType)
	}

	/**
	Adds a filter where the given attribute should be smaller than the given value.
	
	- parameter attributeName: The name of the attribute to filter on.
	- parameter smallerThen:   The value to check for.
	
	- returns: The query
	*/
	public mutating func whereAttribute(attributeName: String, lessThan: AnyObject) {
		addPredicateWithField(attributeName, value: lessThan, type: .LessThanPredicateOperatorType)
	}

	/**
	Adds a filter where the given attribute should be less then or equal to the given value.
	
	- parameter attributeName: The name of the attribute to filter on.
	- parameter smallerThen:   The value to check for.
	
	- returns: The query
	*/
	public mutating func whereAttribute(attributeName: String, lessThanOrEqualTo: AnyObject) {
		addPredicateWithField(attributeName, value: lessThanOrEqualTo, type: .LessThanOrEqualToPredicateOperatorType)
	}
	
	/**
	Adds a filter where the given attribute should be greater then the given value.
	
	- parameter attributeName: The name of the attribute to filter on.
	- parameter greaterThen:   The value to check for.
	
	- returns: The query
	*/
	public mutating func whereAttribute(attributeName: String, greaterThan: AnyObject) {
		addPredicateWithField(attributeName, value: greaterThan, type: .GreaterThanPredicateOperatorType)
	}

	/**
	Adds a filter where the given attribute should be greater than or equal to the given value.
	
	- parameter attributeName: The name of the attribute to filter on.
	- parameter greaterThen:   The value to check for.
	
	- returns: The query
	*/
	public mutating func whereAttribute(attributeName: String, greaterThanOrEqualTo: AnyObject) {
		addPredicateWithField(attributeName, value: greaterThanOrEqualTo, type: .GreaterThanOrEqualToPredicateOperatorType)
	}
	
	/**
	Adds a filter where the given relationship should point to the given resource, or the given
	resource should be present in the related resources.
	
	- parameter relationshipName: The name of the relationship to filter on.
	- parameter resource:         The resource that should be related.
	
	- returns: The query
	*/
	public mutating func whereRelationship(relationshipName: String, isOrContains resource: Resource) {
		assert(resource.id != nil, "Attempt to add a where filter on a relationship, but the target resource does not have an id.")
		addPredicateWithField(relationshipName, value: resource.id!, type: .EqualToPredicateOperatorType)
	}
	
	
	// MARK: Sparse fieldsets
	
	/**
	Restricts the fields that should be requested. When not set, all fields will be requested.
	Note: the server may still choose to return only of a select set of fields.
	
	- parameter fieldNames: Names of fields to fetch.
	
	- returns: The query
	*/
	public mutating func restrictFieldsTo(fieldNames: String...) {
		assert(resourceType != nil, "Cannot restrict fields for query without resource type, use `restrictFieldsOfResourceType` or set a resource type.")
		
		if var fields = fields[resourceType!] {
			fields += fieldNames
		} else {
			fields[resourceType!] = fieldNames
		}
	}
	
	/**
	Restricts the fields of a specific resource type that should be requested.
	This method can be used to restrict fields of included resources. When not set, all fields will be requested.
	
	Note: the server may still choose to return only of a select set of fields.
	
	- parameter type:       The resource type for which to restrict the properties.
	- parameter fieldNames: Names of fields to fetch.
	
	- returns: The query
	*/
	public mutating func restrictFieldsOfResourceType(type: String, to fieldNames: String...) {
		if var fields = fields[type] {
			fields += fieldNames
		} else {
			fields[type] = fieldNames
		}
	}
	
	
	// MARK: Sorting
	
	/**
	Sort in ascending order by the the given property. Previously added properties precedence over this property.
	
	- parameter property: The property which to order by.
	
	- returns: The query
	*/
	public mutating func addAscendingOrder(property: String) {
		sortDescriptors.append(NSSortDescriptor(key: property, ascending: true))
	}
	
	/**
	Sort in descending order by the the given property. Previously added properties precedence over this property.
	
	- parameter property: The property which to order by.
	
	- returns: The query
	*/
	public mutating func addDescendingOrder(property: String) {
		sortDescriptors.append(NSSortDescriptor(key: property, ascending: false))
	}
	
	
	// MARK: Pagination
	
	/**
	Paginate the result using the given pagination configuration. Pass nil to remove pagination.
	
	- parameter pagination: The pagination configuration to use.
	
	- returns: The query
	*/
	public mutating func paginate(pagination: Pagination?) {
		self.pagination = pagination
	}
}


// MARK: - Pagination

public protocol Pagination { }

public struct PageBasedPagination: Pagination {
	var pageNumber: Int
	var pageSize: Int
	
	public init(pageNumber: Int, pageSize: Int) {
		self.pageNumber = pageNumber
		self.pageSize = pageSize
	}
}

public struct OffsetBasedPagination: Pagination {
	var offset: Int
	var limit: Int
	
	public init(offset: Int, limit: Int) {
		self.offset = offset
		self.limit = limit
	}
}