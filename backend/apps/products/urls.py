from django.urls import path

from . import views

app_name = "products"

urlpatterns = [
    path("", views.ProductListView.as_view(), name="list"),
    path("create/", views.ProductCreateView.as_view(), name="create"),
    path("update/<int:pk>/", views.ProductUpdateView.as_view(), name="update"),
    path("delete/<int:pk>/", views.ProductDeleteView.as_view(), name="delete"),
    path("upload-image/", views.ProductImageUploadView.as_view(), name="upload-image"),
]
