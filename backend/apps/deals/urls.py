from django.urls import path

from . import views

app_name = "deals"

urlpatterns = [
    path("", views.MerchantDealListView.as_view(), name="list"),
    path("create/", views.DealCreateView.as_view(), name="create"),
    path("nearby/", views.NearbyDealsView.as_view(), name="nearby"),
    path("shop/<int:shop_id>/", views.ShopDealsView.as_view(), name="shop-deals"),
    path("update/<int:pk>/", views.DealUpdateView.as_view(), name="update"),
    path("<int:pk>/", views.DealDetailView.as_view(), name="detail"),
    path("<int:pk>/publish/", views.DealActionView.as_view(action="publish"), name="publish"),
    path("<int:pk>/pause/", views.DealActionView.as_view(action="pause"), name="pause"),
    path("<int:pk>/sold-out/", views.DealActionView.as_view(action="sold-out"), name="sold-out"),
    path("<int:pk>/end/", views.DealActionView.as_view(action="end"), name="end"),
    path("<int:pk>/duplicate/", views.DealActionView.as_view(action="duplicate"), name="duplicate"),
    path("<int:pk>/update-stock/", views.DealActionView.as_view(action="update-stock"), name="update-stock"),
]
