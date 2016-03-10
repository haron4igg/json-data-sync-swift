//
//  Routing.swift
//  Spine
//
//  Created by Ward van Teijlingen on 24-09-14.
//  Copyright (c) 2014 Ward van Teijlingen. All rights reserved.
//

import Foundation

/**
The RouterProtocol declares methods and properties that a router should implement.
The router is used to build URLs for API requests.
*/
public protocol Router {
	/// The base URL of the API.
	var baseURL: NSURL! { get set }
	
	/**
	Returns an NSURL that points to the collection of resources with a given type.
	
	- parameter type: The type of resources.
	
	- returns: The NSURL.
	*/
	func URLForResourceType(type: ResourceType) -> NSURL
	
	func URLForRelationship<T: Resource>(relationship: Relationship, ofResource resource: T) -> NSURL
	
	/**
	Returns an NSURL that represents the given query.
	
	- parameter query: The query to turn into an NSURL.
	
	- returns: The NSURL.
	*/
	func URLForQuery<T: Resource>(query: Query<T>) -> NSURL
}

/**
The built in JSONAPIRouter builds URLs according to the JSON:API specification.

Filters
=======
Only 'equal to' filters are supported. You can subclass Router and override
`queryItemForFilter` to add support for other filtering strategies.

Pagination
==========
Only PageBasedPagination and OffsetBasedPagination are supported. You can subclass Router
and override `queryItemsForPagination` to add support for other pagination strategies.
*/
public class JSONAPIRouter: Router {
	public var baseURL: NSURL!

	public init() { }
	
	public func URLForResourceType(type: ResourceType) -> NSURL {
		return baseURL.URLByAppendingPathComponent(type)
	}
	
	public func URLForRelationship<T: Resource>(relationship: Relationship, ofResource resource: T) -> NSURL {
		let resourceURL = resource.URL ?? URLForResourceType(resource.dynamicType.resourceType).URLByAppendingPathComponent("/\(resource.id!)")
		return resourceURL.URLByAppendingPathComponent("/links/\(relationship.serializedName)")
	}

	public func URLForQuery<T: Resource>(query: Query<T>) -> NSURL {
		var URL: NSURL!
		var preBuiltURL = false
		
		// Base URL
		if let URLString = query.URL?.absoluteString {
			URL = NSURL(string: URLString, relativeToURL: baseURL)
			preBuiltURL = true
		} else if let type = query.resourceType {
			URL = URLForResourceType(type)
		} else {
			assertionFailure("Cannot build URL for query. Query does not have a URL, nor a resource type.")
		}
		
		let URLComponents = NSURLComponents(URL: URL, resolvingAgainstBaseURL: true)!
		var queryItems: [NSURLQueryItem] = URLComponents.queryItems ?? []
		
		// Resource IDs
		if !preBuiltURL {
			if let IDs = query.resourceIDs {
				if IDs.count == 1 {
					URLComponents.path = (URLComponents.path! as NSString).stringByAppendingPathComponent(IDs.first!)
				} else {
					let item = NSURLQueryItem(name: "filter[id]", value: IDs.joinWithSeparator(","))
					setQueryItem(item, forQueryItems: &queryItems)
				}
			}
		}
		
		// Includes
		if !query.includes.isEmpty {
			let item = NSURLQueryItem(name: "include", value: query.includes.joinWithSeparator(","))
			setQueryItem(item, forQueryItems: &queryItems)
		}
		
		// Filters
		for filter in query.filters {
			let item = queryItemForFilter(filter)
			setQueryItem(item, forQueryItems: &queryItems)
		}
		
		// Fields
		for (resourceType, fields) in query.fields {
			let item = NSURLQueryItem(name: "fields[\(resourceType)]", value: fields.joinWithSeparator(","))
			setQueryItem(item, forQueryItems: &queryItems)
		}
		
		// Sorting
		if !query.sortDescriptors.isEmpty {
			let descriptorStrings = query.sortDescriptors.map { descriptor -> String in
				if descriptor.ascending {
					return "+\(descriptor.key!)"
				} else {
					return "-\(descriptor.key!)"
				}
			}
			
			let item = NSURLQueryItem(name: "sort", value: descriptorStrings.joinWithSeparator(","))
			setQueryItem(item, forQueryItems: &queryItems)
		}
		
		// Pagination
		if let pagination = query.pagination {
			for item in queryItemsForPagination(pagination) {
				setQueryItem(item, forQueryItems: &queryItems)
			}
		}

		// Compose URL
		if !queryItems.isEmpty {
			URLComponents.queryItems = queryItems
		}
		
		return URLComponents.URL!
	}
	
	/**
	Returns an NSURLQueryItem that represents the given comparison predicate in an URL.
	By default this method only supports 'equal to' predicates. You can override
	this method to add support for other filtering strategies.
	
	- parameter filter: The NSComparisonPredicate.
	
	- returns: The NSURLQueryItem.
	*/
	public func queryItemForFilter(filter: NSComparisonPredicate) -> NSURLQueryItem {
		assert(filter.predicateOperatorType == .EqualToPredicateOperatorType, "The built in router only supports Query filter expressions of type 'equalTo'")
        
        var format = "filter[\(filter.leftExpression.keyPath)]"
        if let optionals = filter.optionals {
            for value in optionals {
                format += "[\(value)]"
            }
        }
        
		return NSURLQueryItem(name: format, value: "\(filter.rightExpression.constantValue)")
	}

	/**
	Returns an array of NSURLQueryItems that represent the given pagination configuration.
	By default this method only supports the PageBasedPagination and OffsetBasedPagination configurations.
	You can override this method to add support for other pagination strategies.
	
	- parameter pagination: The QueryPagination configuration.
	
	- returns: Array of NSURLQueryItems.
	*/
	public func queryItemsForPagination(pagination: Pagination) -> [NSURLQueryItem] {
		var queryItems = [NSURLQueryItem]()
		
		switch pagination {
		case let pagination as PageBasedPagination:
			queryItems.append(NSURLQueryItem(name: "page[number]", value: String(pagination.pageNumber)))
			queryItems.append(NSURLQueryItem(name: "page[size]", value: String(pagination.pageSize)))
			
		case let pagination as OffsetBasedPagination:
			queryItems.append(NSURLQueryItem(name: "page[offset]", value: String(pagination.offset)))
			queryItems.append(NSURLQueryItem(name: "page[limit]", value: String(pagination.limit)))
			
			
		default:
			assertionFailure("The built in router only supports PageBasedPagination and OffsetBasedPagination")
		}
		
		return queryItems
	}
	
	private func setQueryItem(queryItem: NSURLQueryItem, inout forQueryItems queryItems: [NSURLQueryItem]) {
		queryItems = queryItems.filter { return $0.name != queryItem.name }
		queryItems.append(queryItem)
	}
}


public extension NSComparisonPredicate {
    
    private struct AssociatedKeys {
        static var OptionalsName = "OptionalsName"
    }
    
    var optionals : [AnyObject]? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.OptionalsName) as? [AnyObject]
        }
        set(value) {
            objc_setAssociatedObject(self,&AssociatedKeys.OptionalsName, value, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    convenience init(format: String, optionals: [AnyObject]?=nil) {
        self.init(format: format, UnsafePointer<Void>())
        self.optionals = optionals
    }
    
}


